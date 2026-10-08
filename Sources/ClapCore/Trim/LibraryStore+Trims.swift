import Foundation

/// Where each sample is trimmed (stored in the index only; the audio files are never changed).
extension LibraryStore {
    public func trims() -> [Int64: SampleTrim] {
        let rows = (try? db.query("SELECT sample_id, start_seconds, end_seconds, fade_out FROM sample_trims") {
            ($0.int(0), SampleTrim(start: $0.double(1), end: $0.double(2), fadeOut: $0.double(3)))
        }) ?? []
        return Dictionary(rows, uniquingKeysWith: { _, new in new })
    }

    /// Saves a trim, or with nil removes it (the sample plays and exports in full again).
    public func setTrim(_ trim: SampleTrim?, sampleID: Int64) throws {
        guard let trim else {
            try db.run("DELETE FROM sample_trims WHERE sample_id = ?", [.int(sampleID)])
            return
        }
        try db.run("""
            INSERT INTO sample_trims(sample_id, start_seconds, end_seconds, fade_out) VALUES(?, ?, ?, ?)
            ON CONFLICT(sample_id) DO UPDATE SET start_seconds = excluded.start_seconds,
                end_seconds = excluded.end_seconds, fade_out = excluded.fade_out
            """, [.int(sampleID), .double(trim.start), .double(trim.end), .double(trim.fadeOut)])
    }
}
