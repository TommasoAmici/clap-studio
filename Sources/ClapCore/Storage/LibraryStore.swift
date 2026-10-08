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
    public func addRoot(path: String, transient: Bool = false) throws -> RootRecord {
        try db.run("INSERT OR IGNORE INTO roots(path, transient) VALUES(?, ?)", [.text(path), .int(transient ? 1 : 0)])
        let id = try db.scalarInt("SELECT id FROM roots WHERE path = ?", [.text(path)]) ?? 0
        let isTransient = (try db.scalarInt("SELECT transient FROM roots WHERE id = ?", [.int(id)]) ?? 0) != 0
        return RootRecord(id: id, path: path, isTransient: isTransient)
    }

    /// The library's folders (not temporary ones such as USB sticks).
    public func roots() -> [RootRecord] { allRoots().filter { !$0.isTransient } }

    public func transientRoots() -> [RootRecord] { allRoots().filter(\.isTransient) }

    private func allRoots() -> [RootRecord] {
        (try? db.query("SELECT id, path, transient FROM roots ORDER BY id") {
            RootRecord(id: $0.int(0), path: $0.text(1), isTransient: $0.int(2) != 0)
        }) ?? []
    }

    /// Forgets every temporary root and what was learned about its files.
    public func purgeTransientRoots() throws {
        for root in transientRoots() { try removeRoot(id: root.id) }
    }

    public func removeRoot(id: Int64) throws {
        try db.transaction {
            let sub = "SELECT id FROM samples WHERE root_id = ?"
            try db.run("DELETE FROM sample_coords WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM cue_points WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM usage_events WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM collection_items WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM sample_tags WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM sample_moods WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM sample_trims WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM sample_segments WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM segment_sounds WHERE sample_id IN (\(sub))", [.int(id)])
            try db.run("DELETE FROM recording_species WHERE sample_id IN (\(sub))", [.int(id)])
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
                            UPDATE samples SET size = ?, mtime = ?, status = 'pending', error = NULL,
                                desc_version = 0,
                                category_version = NULL WHERE id = ?
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
                case let .success(id, duration, sr, ch, embedding, fingerprint, version, cues, descriptors, segments):
                    try db.run("""
                        UPDATE samples SET duration = ?, sample_rate = ?, channels = ?, embedding = ?,
                            fingerprint = COALESCE(?, fingerprint), model_version = ?, status = 'ok',
                            error = NULL, indexed_at = ? WHERE id = ?
                        """, [.double(duration), .double(sr), .int(Int64(ch)),
                              .blob(VectorCodec.encodeFloat16(embedding)),
                              fingerprint.map { .text($0) } ?? .null, .text(version), .double(now), .int(id)])
                    try importFileCues(sampleID: id, cues)
                    try writeDescriptors(id, descriptors)
                    try writeSegments(id, segments)
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

    /// The library's samples (not those of temporary roots).
    public func loadSamples() -> [SampleRecord] { querySamples(extraFilter: "AND r.transient = 0", params: []) }

    /// Samples of temporary roots, such as a USB stick.
    public func loadTransientSamples() -> [SampleRecord] { querySamples(extraFilter: "AND r.transient = 1", params: []) }

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
                   (SELECT COUNT(*) FROM cue_points c WHERE c.sample_id = s.id),
                   s.loudness, s.peak, s.crest, s.centroid, s.is_loop, s.bpm, s.bpm_manual, s.pitch_hz, s.key_name,
                   s.category, s.category_manual, s.favorite, s.hidden,
                   (SELECT group_concat(tag, char(31)) FROM sample_tags t WHERE t.sample_id = s.id),
                   (SELECT group_concat(mood, char(31)) FROM sample_moods m WHERE m.sample_id = s.id),
                   (SELECT group_concat(sound, char(31)) FROM (SELECT DISTINCT sound FROM segment_sounds n WHERE n.sample_id = s.id)),
                   (SELECT group_concat(common, char(31)) FROM (SELECT DISTINCT common FROM recording_species b
                        WHERE b.sample_id = s.id AND b.allowed = 1 AND b.confidence >= \(Self.reportedConfidence)))
            FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status IN ('ok', 'pending') \(extraFilter)
            """, params) {
            SampleRecord(
                id: $0.int(0), rootID: $0.int(1), rootPath: $0.text(2), relPath: $0.text(3),
                name: $0.text(4), ext: $0.text(5), duration: $0.double(6), sampleRate: $0.double(7),
                channels: Int($0.int(8)), size: $0.int(9), mtime: $0.double(10),
                status: SampleStatus(rawValue: $0.text(11)) ?? .pending,
                useCount: Int($0.int(12)), lastUsed: $0.isNull(13) ? nil : $0.double(13),
                cueCount: Int($0.int(14)),
                loudnessDB: $0.optDouble(15), peakDB: $0.optDouble(16), crestDB: $0.optDouble(17),
                centroidHz: $0.optDouble(18), isLoop: $0.isNull(19) ? nil : $0.int(19) != 0,
                bpm: $0.optDouble(20), bpmManual: $0.optDouble(21), pitchHz: $0.optDouble(22),
                keyName: $0.isNull(23) ? nil : $0.text(23),
                category: $0.isNull(24) ? nil : $0.text(24), categoryManual: $0.isNull(25) ? nil : $0.text(25),
                favorite: $0.int(26) != 0, hidden: $0.int(27) != 0,
                tags: $0.isNull(28) ? [] : $0.text(28).split(separator: "\u{1F}").map(String.init).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                moods: $0.isNull(29) ? [] : SoundMoods.sorted($0.text(29).split(separator: "\u{1F}").map(String.init)),
                sounds: $0.isNull(30) ? [] : SoundCategories.sortedSounds($0.text(30).split(separator: "\u{1F}").map(String.init)),
                species: $0.isNull(31) ? [] : $0.text(31).split(separator: "\u{1F}").map(String.init).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
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
