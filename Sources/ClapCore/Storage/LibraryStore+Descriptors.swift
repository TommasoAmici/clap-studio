import Foundation

/// Persistence of measured descriptors and the user's corrections to them.
extension LibraryStore {
    /// Must run inside a transaction when called from `save(results:)`.
    func writeDescriptors(_ id: Int64, _ d: SoundDescriptors?) throws {
        guard let d else { return }
        try db.run("""
            UPDATE samples SET loudness = ?, peak = ?, crest = ?, centroid = ?, is_loop = ?, bpm = ?, bpm_conf = ?,
                pitch_hz = ?, key_name = ?, desc_version = ? WHERE id = ?
            """, [.double(d.loudnessDB), .double(d.peakDB), .double(d.crestDB), .double(d.centroidHz),
                  .int(d.isLoop ? 1 : 0), d.bpm.map { .double($0) } ?? .null, .double(d.bpmConfidence),
                  d.pitchHz.map { .double($0) } ?? .null, d.keyName.map { .text($0) } ?? .null,
                  .int(Int64(SoundDescriptors.version)), .int(id)])
    }

    /// Indexed samples that have no descriptors yet (libraries indexed before this feature, or analyser upgrades).
    public func descriptorJobs(limit: Int) -> [IndexJob] {
        (try? db.query("""
            SELECT s.id, r.path, s.rel_path FROM samples s JOIN roots r ON r.id = s.root_id
            WHERE s.status = 'ok' AND s.desc_version < ? AND NOT \(FieldRecording.sqlIs("s")) ORDER BY s.id LIMIT ?
            """, [.int(Int64(SoundDescriptors.version)), .int(Int64(limit))]) {
            IndexJob(id: $0.int(0), url: URL(fileURLWithPath: $0.text(1)).appendingPathComponent($0.text(2)))
        }) ?? []
    }

    public func descriptorBacklog() -> Int {
        Int((try? db.scalarInt("""
            SELECT COUNT(*) FROM samples WHERE status = 'ok' AND desc_version < ? AND NOT \(FieldRecording.sqlIs())
            """, [.int(Int64(SoundDescriptors.version))])) ?? 0)
    }

    /// Saves backfill results. Files that could not be analysed are marked done (with no values)
    /// so they are not retried on every launch.
    public func saveDescriptors(_ results: [(id: Int64, descriptors: SoundDescriptors?)]) throws {
        try db.transaction {
            for r in results {
                if let d = r.descriptors { try writeDescriptors(r.id, d) }
                else { try db.run("UPDATE samples SET desc_version = ? WHERE id = ?",
                                  [.int(Int64(SoundDescriptors.version)), .int(r.id)]) }
            }
        }
    }

    /// The user's own BPM for a loop (pass nil to go back to the detected value).
    public func setManualBPM(sampleID: Int64, _ bpm: Double?) throws {
        try db.run("UPDATE samples SET bpm_manual = ? WHERE id = ?", [bpm.map { .double($0) } ?? .null, .int(sampleID)])
    }

    /// Several samples at once, each with its own value (nil goes back to the detected tempo).
    public func setManualBPMs(_ values: [(id: Int64, bpm: Double?)]) throws {
        try db.transaction {
            for value in values {
                try db.run("UPDATE samples SET bpm_manual = ? WHERE id = ?",
                           [value.bpm.map { .double($0) } ?? .null, .int(value.id)])
            }
        }
    }
}
