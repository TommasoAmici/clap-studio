import Foundation

/// A source piece in a joined file; its name remains available when the source is removed.
public struct JoinedPart: Sendable {
    public let sourceID: Int64?
    public let sourceURL: URL
    public let name: String
    public let sourceStartFrame: Int64
    public let startFrame: Int64
    public let endFrame: Int64
}

extension LibraryStore {
    /// Keeps the exact published pieces, even if their output folder has not been indexed yet.
    public func recordJoinedOutputs(_ outputs: [JoinedOutput], sources: [JoinSource]) throws {
        let files = try outputs.map { output -> (JoinedOutput, JoinedFileFingerprint.Snapshot) in
            guard let fingerprint = JoinedFileFingerprint.snapshot(url: output.url) else { throw JoinError.verificationFailed }
            return (output, fingerprint)
        }
        try db.transaction {
            for (output, fingerprint) in files {
                guard fingerprint.isCurrent(at: output.url) else { throw JoinError.verificationFailed }
                let path = output.url.standardizedFileURL.path
                try db.run("INSERT INTO joined_files(path, fingerprint, verified) VALUES(?, ?, 1)",
                           [.text(path), .text(fingerprint.digest)])
                for (ordinal, region) in output.regions.enumerated() {
                    guard sources.indices.contains(region.sourceIndex) else { throw JoinError.invalidSettings }
                    let source = sources[region.sourceIndex]
                    // A removed folder's ID can be reused while rendering; verify the path too.
                    let currentPath = try source.sampleID.flatMap { id in
                        try db.query("""
                            SELECT r.path, s.rel_path FROM samples s JOIN roots r ON r.id = s.root_id
                            WHERE s.id = ?
                            """, [.int(id)]) {
                                URL(fileURLWithPath: $0.text(0)).appendingPathComponent($0.text(1)).standardizedFileURL
                            }.first
                    }
                    let id: SQLValue = currentPath == source.url.standardizedFileURL
                        ? source.sampleID.map { .int($0) } ?? .null : .null
                    try db.run("""
                        INSERT INTO joined_parts(joined_path, ordinal, source_id, source_path, name,
                                                 source_start, start_frame, end_frame)
                        VALUES(?, ?, (SELECT id FROM samples WHERE id = ?), ?, ?, ?, ?, ?)
                        """, [.text(path), .int(Int64(ordinal)), id, .text(source.url.standardizedFileURL.path),
                              .text(source.name), .int(region.sourceStartFrame), .int(region.startFrame), .int(region.endFrame)])
                }
            }
        }
    }

    public func isJoinedFile(at url: URL) -> Bool {
        ((try? db.scalarInt("SELECT 1 FROM joined_files WHERE path = ? AND verified = 1", [.text(url.standardizedFileURL.path)])) ?? nil) != nil
    }

    public func joinedParts(for url: URL) -> [JoinedPart] {
        (try? db.query("""
            SELECT source_id, source_path, name, source_start, start_frame, end_frame
            FROM joined_parts WHERE joined_path = ? ORDER BY ordinal
            """, [.text(url.standardizedFileURL.path)]) {
                JoinedPart(sourceID: $0.isNull(0) ? nil : $0.int(0), sourceURL: URL(fileURLWithPath: $0.text(1)),
                           name: $0.text(2), sourceStartFrame: $0.int(3), startFrame: $0.int(4), endFrame: $0.int(5))
            }) ?? []
    }

    /// Resolve each root once so large libraries can compare relative paths cheaply.
    public func joinedRelativePathsByRoot() -> [Int64: Set<String>] {
        joinedRelativePathsByRoot(includeUnverified: false)
    }

    func joinedRelativePathsByRoot(includeUnverified: Bool) -> [Int64: Set<String>] {
        let sql = includeUnverified ? "SELECT path FROM joined_files" : "SELECT path FROM joined_files WHERE verified = 1"
        let paths = (try? db.query(sql) { $0.text(0) }) ?? []
        guard !paths.isEmpty else { return [:] }
        let roots = (try? db.query("SELECT id, path FROM roots") { ($0.int(0), $0.text(1)) }) ?? []
        var found: [Int64: Set<String>] = [:]
        for (id, path) in roots {
            let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
            let prefix = root == "/" ? "/" : root + "/"
            for joined in paths where joined.hasPrefix(prefix) {
                found[id, default: []].insert(String(joined.dropFirst(prefix.count)))
            }
        }
        return found
    }

    struct JoinedIdentity {
        let fingerprint: String?
        let verificationState: Int64
        var verified: Bool { verificationState == 1 }
    }

    func joinedIdentity(at url: URL) throws -> JoinedIdentity? {
        try db.query("SELECT fingerprint, verified FROM joined_files WHERE path = ?", [.text(url.standardizedFileURL.path)]) {
            JoinedIdentity(fingerprint: $0.isNull(0) ? nil : $0.text(0), verificationState: $0.int(1))
        }.first
    }

    /// Keeps unreadable links for a later retry, and forgets links when readable bytes no longer match.
    func verifyJoinedFile(at url: URL, snapshot: JoinedFileFingerprint.Snapshot?, scanned: ScannedFile,
                          previous: String? = nil, legacyCurrent: String? = nil) throws {
        guard let identity = try joinedIdentity(at: url) else { return }
        let path = SQLValue.text(url.standardizedFileURL.path)
        guard let snapshot, snapshot.isCurrent(at: url, scanned: scanned) else {
            try db.run("UPDATE joined_files SET verified = 0 WHERE path = ?", [path])
            return
        }
        let current = snapshot.digest
        if let expected = identity.fingerprint, expected != current {
            try db.run("DELETE FROM joined_files WHERE path = ?", [path])
            return
        }
        // Version 15 had no full digest; use its stored ordinary fingerprint if one exists.
        if identity.fingerprint == nil, let previous {
            guard let legacyCurrent else {
                try db.run("UPDATE joined_files SET verified = 0 WHERE path = ?", [path])
                return
            }
            if previous != legacyCurrent {
                try db.run("DELETE FROM joined_files WHERE path = ?", [path])
                return
            }
        }
        try db.run("UPDATE joined_files SET fingerprint = ?, verified = 1 WHERE path = ?", [.text(current), path])
    }

    /// Hashes app-authored WAV writes before their database transaction starts.
    func joinedFingerprintForWrite(sampleID: Int64, fingerprint: String?) throws -> JoinedFileFingerprint.Snapshot? {
        guard fingerprint != nil, let url = try joinedSampleURL(sampleID), try joinedIdentity(at: url) != nil else { return nil }
        return JoinedFileFingerprint.snapshot(url: url)
    }

    func updateJoinedFingerprint(sampleID: Int64, snapshot: JoinedFileFingerprint.Snapshot?) throws {
        guard let url = try joinedSampleURL(sampleID), try joinedIdentity(at: url) != nil else { return }
        let path = SQLValue.text(url.standardizedFileURL.path)
        guard let snapshot else {
            try db.run("UPDATE joined_files SET verified = 0 WHERE path = ?", [path])
            return
        }
        try db.run("UPDATE joined_files SET fingerprint = ?, verified = ? WHERE path = ?",
                   [.text(snapshot.digest), .int(snapshot.isCurrent(at: url) ? 1 : 0), path])
    }

    private func joinedSampleURL(_ id: Int64) throws -> URL? {
        try db.query("""
            SELECT r.path, s.rel_path FROM samples s JOIN roots r ON r.id = s.root_id WHERE s.id = ?
            """, [.int(id)], { URL(fileURLWithPath: $0.text(0)).appendingPathComponent($0.text(1)) }).first
    }
}
