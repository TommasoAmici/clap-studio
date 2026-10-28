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
        try db.transaction {
            for output in outputs {
                let path = output.url.standardizedFileURL.path
                try db.run("INSERT INTO joined_files(path) VALUES(?)", [.text(path)])
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
        ((try? db.scalarInt("SELECT 1 FROM joined_files WHERE path = ?", [.text(url.standardizedFileURL.path)])) ?? nil) != nil
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
        let paths = (try? db.query("SELECT path FROM joined_files") { $0.text(0) }) ?? []
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

}
