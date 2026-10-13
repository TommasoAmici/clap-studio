import Foundation

/// Where each sample is trimmed and how it is edited (stored in the index only; the audio files are never changed).
extension LibraryStore {
    public func trims() -> [Int64: SampleTrim] {
        let rows = (try? db.query("""
            SELECT sample_id, start_seconds, end_seconds, fade_out, reverse, gain_db, speed, low_pass, high_pass FROM sample_trims
            """) {
            ($0.int(0), SampleTrim(start: $0.double(1), end: $0.double(2), fadeOut: $0.double(3),
                                   edit: SampleEdit(reverse: $0.int(4) != 0, gainDB: $0.double(5), speedSemitones: $0.double(6),
                                                    lowPassHz: $0.optDouble(7), highPassHz: $0.optDouble(8))))
        }) ?? []
        return Dictionary(rows, uniquingKeysWith: { _, new in new })
    }

    /// Saves a trim, or with nil removes it (the sample plays and exports in full again).
    public func setTrim(_ trim: SampleTrim?, sampleID: Int64) throws {
        guard let trim else {
            try db.run("DELETE FROM sample_trims WHERE sample_id = ?", [.int(sampleID)])
            return
        }
        let edit = trim.edit
        try db.run("""
            INSERT INTO sample_trims(sample_id, start_seconds, end_seconds, fade_out, reverse, gain_db, speed, low_pass, high_pass)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(sample_id) DO UPDATE SET start_seconds = excluded.start_seconds,
                end_seconds = excluded.end_seconds, fade_out = excluded.fade_out, reverse = excluded.reverse,
                gain_db = excluded.gain_db, speed = excluded.speed, low_pass = excluded.low_pass, high_pass = excluded.high_pass
            """, [.int(sampleID), .double(trim.start), .double(trim.end), .double(trim.fadeOut), .int(edit.reverse ? 1 : 0),
                  .double(edit.gainDB), .double(edit.speedSemitones), edit.lowPassHz.map { .double($0) } ?? .null,
                  edit.highPassHz.map { .double($0) } ?? .null])
    }
}
