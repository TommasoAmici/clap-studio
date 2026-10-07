import Foundation

/// High-level persistent store: roots, samples, embeddings, usage.
/// Everything expensive to compute lives here so relaunching never re-indexes.
public final class LibraryStore: @unchecked Sendable {
    public let db: SQLiteDB

    public init(path: String) throws {
        db = try SQLiteDB(path: path)
        try db.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
        try Schema.migrate(db)
    }

    /// `~/Library/Application Support/ClapStudio/library.sqlite`
    /// Set `CLAP_DATA_DIR` to keep a separate library (useful for demos and testing).
    public static func defaultURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAP_DATA_DIR"] {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("library.sqlite")
        }
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("ClapStudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.sqlite")
    }

    // MARK: meta

    public func meta(_ key: String) -> String? {
        (try? db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { $0.text(0) })?.first
    }

    public func setMeta(_ key: String, _ value: String) throws {
        try db.run("INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                   [.text(key), .text(value)])
    }

    // MARK: roots

    @discardableResult
    public func addRoot(path: String) throws -> RootRecord {
        try db.run("INSERT OR IGNORE INTO roots(path) VALUES(?)", [.text(path)])
        let id = try db.scalarInt("SELECT id FROM roots WHERE path = ?", [.text(path)]) ?? 0
        return RootRecord(id: id, path: path)
    }

    public func roots() -> [RootRecord] {
        (try? db.query("SELECT id, path FROM roots ORDER BY id") {
            RootRecord(id: $0.int(0), path: $0.text(1))
        }) ?? []
    }

    public func removeRoot(id: Int64) throws {
        try db.transaction {
            let sub = "SELECT id FROM samples WHERE root_id = ?"
            try db.run("DELETE FROM sample_coords WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM cue_points WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM usage_events WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM samples WHERE root_id = ?", [.int(id)])
            try db.run("DELETE FROM roots WHERE id = ?", [.int(id)])
        }
    }

    // MARK: scan sync

    /// Reconciles the DB with a fresh scan. `fingerprint` is only invoked for
    /// paths not yet known, to detect moved or renamed files.
    @discardableResult
    public func sync(rootID: Int64, scanned: [ScannedFile],
                     fingerprint: (String) -> String?) throws -> SyncResult {
        struct Existing { let id: Int64; let relPath: String; let size: Int64; let mtime: Double
                          let fingerprint: String?; let status: String }
        var result = SyncResult()
        let existing = try db.query(
            "SELECT id, rel_path, size, mtime, fingerprint, status FROM samples WHERE root_id = ?",
            [.int(rootID)]) {
            Existing(id: $0.int(0), relPath: $0.text(1), size: $0.int(2), mtime: $0.double(3),
                     fingerprint: $0.isNull(4) ? nil : $0.text(4), status: $0.text(5))
        }
        let byPath = Dictionary(uniqueKeysWithValues: existing.map { ($0.relPath, $0) })
        let scannedPaths = Set(scanned.map(\.relPath))

        var vanished: [String: [Existing]] = [:]
        for e in existing where !scannedPaths.contains(e.relPath) {
            if let fp = e.fingerprint { vanished[fp, default: []].append(e) }
        }
        var claimed = Set<Int64>()

        try db.transaction {
            for file in scanned {
                if let e = byPath[file.relPath] {
                    if e.size == file.size && abs(e.mtime - file.mtime) < 0.001 {
                        if e.status == SampleStatus.missing.rawValue { try restore(e.id) }
                        result.unchanged += 1
                    } else {
                        try db.run("""
                            UPDATE samples SET size = ?, mtime = ?, status = 'pending', error = NULL
                            WHERE id = ?
                            """, [.int(file.size), .double(file.mtime), .int(e.id)])
                        result.changed += 1
                    }
                    continue
                }
                let fp = fingerprint(file.relPath)
                if let fp, let match = vanished[fp]?.first(where: { !claimed.contains($0.id) }) {
                    claimed.insert(match.id)
                    try db.run("UPDATE samples SET rel_path = ?, name = ?, ext = ?, size = ?, mtime = ? WHERE id = ?",
                               [.text(file.relPath), .text(Self.baseName(file.relPath)),
                                .text(Self.ext(file.relPath)), .int(file.size), .double(file.mtime), .int(match.id)])
                    try restore(match.id)
                    result.moved += 1
                } else {
                    try db.run("""
                        INSERT INTO samples(root_id, rel_path, name, ext, size, mtime, fingerprint, status)
                        VALUES(?, ?, ?, ?, ?, ?, ?, 'pending')
                        """, [.int(rootID), .text(file.relPath), .text(Self.baseName(file.relPath)),
                              .text(Self.ext(file.relPath)), .int(file.size), .double(file.mtime),
                              fp.map { .text($0) } ?? .null])
                    result.added += 1
                }
            }
            for e in existing where !scannedPaths.contains(e.relPath) && !claimed.contains(e.id) {
                if e.status != SampleStatus.missing.rawValue {
                    try db.run("UPDATE samples SET status = 'missing' WHERE id = ?", [.int(e.id)])
                }
                result.missing += 1
            }
            try db.run("UPDATE roots SET last_scan = ? WHERE id = ?",
                       [.double(Date().timeIntervalSince1970), .int(rootID)])
        }
        return result
    }

    private func restore(_ id: Int64) throws {
        try db.run("""
            UPDATE samples SET status = CASE
                WHEN embedding IS NOT NULL THEN 'ok'
                WHEN error IS NOT NULL THEN 'failed' ELSE 'pending' END
            WHERE id = ?
            """, [.int(id)])
    }

    static func baseName(_ rel: String) -> String {
        ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func ext(_ rel: String) -> String { (rel as NSString).pathExtension.lowercased() }

    // MARK: indexing jobs

    /// Re-queues samples embedded by a different model so they get re-embedded.
    @discardableResult
    public func markStale(currentModelVersion: String) throws -> Int {
        let n = try db.scalarInt("""
            SELECT COUNT(*) FROM samples WHERE status = 'ok' AND COALESCE(model_version, '') != ?
            """, [.text(currentModelVersion)]) ?? 0
        if n > 0 {
            try db.run("UPDATE samples SET status = 'pending' WHERE status = 'ok' AND COALESCE(model_version, '') != ?",
                       [.text(currentModelVersion)])
        }
        return Int(n)
    }

    public func pendingCount() -> Int {
        Int((try? db.scalarInt("SELECT COUNT(*) FROM samples WHERE status = 'pending'")) ?? 0)
    }

    public func pendingJobs(limit: Int) -> [IndexJob] {
        (try? db.query("""
            SELECT s.id, r.path, s.rel_path FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status = 'pending' ORDER BY s.id LIMIT ?
            """, [.int(Int64(limit))]) {
            IndexJob(id: $0.int(0), url: URL(fileURLWithPath: $0.text(1)).appendingPathComponent($0.text(2)))
        }) ?? []
    }

    /// Commits a batch atomically so an interrupted run loses almost nothing.
    public func save(results: [IndexResult]) throws {
        let now = Date().timeIntervalSince1970
        try db.transaction {
            for r in results {
                switch r {
                case let .success(id, duration, sr, ch, embedding, fingerprint, version, cues):
                    try db.run("""
                        UPDATE samples SET duration = ?, sample_rate = ?, channels = ?, embedding = ?,
                            fingerprint = COALESCE(?, fingerprint), model_version = ?, status = 'ok',
                            error = NULL, indexed_at = ? WHERE id = ?
                        """, [.double(duration), .double(sr), .int(Int64(ch)),
                              .blob(VectorCodec.encodeFloat16(embedding)),
                              fingerprint.map { .text($0) } ?? .null, .text(version), .double(now), .int(id)])
                    try importFileCues(sampleID: id, cues)
                case let .failure(id, message):
                    try db.run("UPDATE samples SET status = 'failed', error = ?, indexed_at = ? WHERE id = ?",
                               [.text(message), .double(now), .int(id)])
                }
            }
        }
    }

    public func failedCount() -> Int {
        Int((try? db.scalarInt("SELECT COUNT(*) FROM samples WHERE status = 'failed'")) ?? 0)
    }

    // MARK: loading

    public func loadSamples() -> [SampleRecord] { querySamples(extraFilter: "", params: []) }

    public func sample(id: Int64) -> SampleRecord? {
        querySamples(extraFilter: "AND s.id = ?", params: [.int(id)]).first
    }

    private func querySamples(extraFilter: String, params: [SQLValue]) -> [SampleRecord] {
        (try? db.query("""
            SELECT s.id, s.root_id, r.path, s.rel_path, s.name, s.ext,
                   COALESCE(s.duration, 0), COALESCE(s.sample_rate, 0), COALESCE(s.channels, 0),
                   s.size, s.mtime, s.status,
                   (SELECT COUNT(*) FROM usage_events u WHERE u.sample_id = s.id),
                   (SELECT MAX(ts) FROM usage_events u WHERE u.sample_id = s.id),
                   (SELECT COUNT(*) FROM cue_points c WHERE c.sample_id = s.id)
            FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status IN ('ok', 'pending') \(extraFilter)
            """, params) {
            SampleRecord(
                id: $0.int(0), rootID: $0.int(1), rootPath: $0.text(2), relPath: $0.text(3),
                name: $0.text(4), ext: $0.text(5), duration: $0.double(6), sampleRate: $0.double(7),
                channels: Int($0.int(8)), size: $0.int(9), mtime: $0.double(10),
                status: SampleStatus(rawValue: $0.text(11)) ?? .pending,
                useCount: Int($0.int(12)), lastUsed: $0.isNull(13) ? nil : $0.double(13),
                cueCount: Int($0.int(14)))
        }) ?? []
    }

    // MARK: usage

    public func recordGrab(sampleID: Int64, at date: Date = Date()) throws {
        try db.run("INSERT INTO usage_events(sample_id, ts) VALUES(?, ?)",
                   [.int(sampleID), .double(date.timeIntervalSince1970)])
    }

    public func usage(sampleID: Int64) -> (count: Int, last: Double?) {
        let rows = (try? db.query("SELECT COUNT(*), MAX(ts) FROM usage_events WHERE sample_id = ?",
                                  [.int(sampleID)]) { (Int($0.int(0)), $0.isNull(1) ? nil : $0.double(1)) }) ?? []
        return rows.first.map { (count: $0.0, last: $0.1) } ?? (0, nil)
    }

    /// Updates stored file attributes after the app itself rewrote a file.
    public func updateFileAttributes(sampleID: Int64, size: Int64, mtime: Double, fingerprint: String?) throws {
        try db.run("UPDATE samples SET size = ?, mtime = ?, fingerprint = COALESCE(?, fingerprint) WHERE id = ?",
                   [.int(size), .double(mtime), fingerprint.map { .text($0) } ?? .null, .int(sampleID)])
    }
}
