import Foundation

/// Cue point persistence. The DB is the source of truth; `CueFileSync` mirrors edits into WAV files.
extension LibraryStore {
    public func cues(sampleID: Int64) -> [CuePoint] {
        (try? db.query("""
            SELECT id, sample_id, position_frames, label, source, file_synced
            FROM cue_points WHERE sample_id = ? ORDER BY position_frames, id
            """, [.int(sampleID)]) {
            CuePoint(id: $0.int(0), sampleID: $0.int(1), positionFrames: $0.int(2), label: $0.text(3),
                     source: CueSource(rawValue: $0.text(4)) ?? .user, fileSynced: $0.int(5) != 0)
        }) ?? []
    }

    public func cuesDirty(sampleID: Int64) -> Bool {
        ((try? db.scalarInt("SELECT cues_dirty FROM samples WHERE id = ?", [.int(sampleID)])) ?? 0) != 0
    }

    /// Samples whose cues changed in the app and have not been written to their file yet.
    public func dirtyCueSampleIDs() -> [Int64] {
        (try? db.query("SELECT id FROM samples WHERE cues_dirty = 1 AND status = 'ok' ORDER BY id") { $0.int(0) }) ?? []
    }

    private func markDirty(_ sampleID: Int64) throws {
        try db.run("UPDATE samples SET cues_dirty = 1 WHERE id = ?", [.int(sampleID)])
    }

    @discardableResult
    public func insertCue(sampleID: Int64, frame: Int64, label: String = "", source: CueSource = .user,
                          fileSynced: Bool = false, id: Int64? = nil) throws -> CuePoint {
        try db.run("INSERT INTO cue_points(id, sample_id, position_frames, label, source, file_synced) VALUES(?, ?, ?, ?, ?, ?)",
                   [id.map { .int($0) } ?? .null, .int(sampleID), .int(frame), .text(label),
                    .text(source.rawValue), .int(fileSynced ? 1 : 0)])
        let newID = id ?? db.lastInsertRowID
        if source == .user { try markDirty(sampleID) }
        return CuePoint(id: newID, sampleID: sampleID, positionFrames: frame, label: label,
                        source: source, fileSynced: fileSynced)
    }

    public func updateCue(id: Int64, frame: Int64? = nil, label: String? = nil) throws {
        guard let cue = cue(id: id) else { return }
        try db.run("UPDATE cue_points SET position_frames = ?, label = ?, file_synced = 0 WHERE id = ?",
                   [.int(frame ?? cue.positionFrames), .text(label ?? cue.label), .int(id)])
        try markDirty(cue.sampleID)
    }

    public func deleteCue(id: Int64) throws {
        guard let cue = cue(id: id) else { return }
        try db.run("DELETE FROM cue_points WHERE id = ?", [.int(id)])
        try markDirty(cue.sampleID)
    }

    public func cue(id: Int64) -> CuePoint? {
        (try? db.query("SELECT id, sample_id, position_frames, label, source, file_synced FROM cue_points WHERE id = ?",
                       [.int(id)]) {
            CuePoint(id: $0.int(0), sampleID: $0.int(1), positionFrames: $0.int(2), label: $0.text(3),
                     source: CueSource(rawValue: $0.text(4)) ?? .user, fileSynced: $0.int(5) != 0)
        })?.first
    }

    /// Merges cues read from the file into the DB without losing app-only cues.
    public func importFileCues(sampleID: Int64, _ fileCues: [FileCue]) throws {
        let existing = cues(sampleID: sampleID)
        let dirty = cuesDirty(sampleID: sampleID)
        let fileFrames = Set(fileCues.map(\.frame))

        for fc in fileCues {
            if let match = existing.first(where: { $0.positionFrames == fc.frame }) {
                try db.run("""
                    UPDATE cue_points SET file_synced = 1, source = 'file',
                        label = CASE WHEN ? != '' THEN ? ELSE label END WHERE id = ?
                    """, [.text(fc.label), .text(fc.label), .int(match.id)])
            } else {
                try insertCue(sampleID: sampleID, frame: fc.frame, label: fc.label, source: .file, fileSynced: true)
            }
        }
        // Cues that used to be in the file and were removed externally.
        if !dirty {
            for old in existing where old.source == .file && old.fileSynced && !fileFrames.contains(old.positionFrames) {
                try db.run("DELETE FROM cue_points WHERE id = ?", [.int(old.id)])
            }
        }
    }

    /// Writes the app's cues into a WAV file and keeps the DB
    /// consistent so the file is not re-embedded afterwards.
    @discardableResult
    public func writeCuesToFile(sample: SampleRecord, keepBackup: Bool) throws -> URL? {
        let fileCues = cues(sampleID: sample.id).map { FileCue(frame: $0.positionFrames, label: $0.label) }
        let backup = try WavCueWriter.write(cues: fileCues, to: sample.url, keepBackup: keepBackup)
        let attrs = try FileManager.default.attributesOfItem(atPath: sample.url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? sample.size
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? sample.mtime
        let fingerprint = FileFingerprint.compute(url: sample.url)
        let joined = try joinedFingerprintForWrite(sampleID: sample.id, fingerprint: fingerprint)
        try db.transaction {
            try updateFileAttributes(sampleID: sample.id, size: size, mtime: mtime, fingerprint: fingerprint, joined: joined)
            try db.run("UPDATE cue_points SET file_synced = 1, source = 'file' WHERE sample_id = ?", [.int(sample.id)])
            try db.run("UPDATE samples SET cues_dirty = 0 WHERE id = ?", [.int(sample.id)])
        }
        return backup
    }
}
