import Foundation

/// Persistence of the segments of field recordings.
extension LibraryStore {
    /// Changes how selected files are read and queues just those files for fresh analysis.
    public func setRegularSamples(_ values: [(id: Int64, regular: Bool, category: String?)]) throws {
        try db.transaction {
            for value in values {
                try db.run("""
                    UPDATE samples SET regular_sample = ?, category_manual = ?, category = NULL,
                        category_version = NULL, status = CASE WHEN status = 'missing' THEN status ELSE 'pending' END
                    WHERE id = ?
                    """, [.int(value.regular ? 1 : 0), value.category.map(SQLValue.text) ?? .null, .int(value.id)])
                try writeSegments(value.id, [])
                try db.run("DELETE FROM sample_moods WHERE sample_id = ?", [.int(value.id)])
            }
            try db.run("DELETE FROM meta WHERE key IN ('mood_state', 'sounds_state')")
        }
    }

    /// Replaces a sample's segments. Must run inside a transaction. A sample without segments is not a field
    /// recording (any more), so its `segment_version` goes back to 0.
    func writeSegments(_ id: Int64, _ segments: [SegmentEmbedding]) throws {
        try db.run("DELETE FROM sample_segments WHERE sample_id = ?", [.int(id)])
        try db.run("DELETE FROM segment_sounds WHERE sample_id = ?", [.int(id)])
        // The audio was read again, so the birds in it must be listened for again.
        try db.run("DELETE FROM recording_species WHERE sample_id = ?", [.int(id)])
        try db.run("UPDATE samples SET species_version = NULL WHERE id = ?", [.int(id)])
        for (i, s) in segments.enumerated() {
            try db.run("INSERT INTO sample_segments(sample_id, idx, start, end, embedding) VALUES(?, ?, ?, ?, ?)",
                       [.int(id), .int(Int64(i)), .double(s.start), .double(s.end),
                        .blob(VectorCodec.encodeFloat16(s.embedding))])
        }
        try db.run("UPDATE samples SET segment_version = ? WHERE id = ?",
                   [.int(segments.isEmpty ? 0 : Int64(FieldRecording.segmenterVersion)), .int(id)])
    }

    public func segments(sampleID: Int64) -> [SegmentEmbedding] {
        (try? db.query("SELECT start, end, embedding FROM sample_segments WHERE sample_id = ? ORDER BY idx",
                       [.int(sampleID)]) {
            SegmentEmbedding(start: $0.double(0), end: $0.double(1), embedding: VectorCodec.decodeFloat16($0.blob(2)))
        }) ?? []
    }

    public func segmentCount(sampleID: Int64) -> Int {
        Int((try? db.scalarInt("SELECT COUNT(*) FROM sample_segments WHERE sample_id = ?", [.int(sampleID)])) ?? 0)
    }

    /// Streams the segments of library field recordings (not temporary roots) made with `modelVersion`,
    /// in chunks of ids, spans and flat embeddings.
    public func forEachSegmentChunk(modelVersion: String, chunkSize: Int = 4096,
                                    _ body: ([Int64], [TimeSpan], [Float]) -> Void) throws {
        var lastID: Int64 = 0, lastIdx: Int64 = -1
        while true {
            let rows = try db.query("""
                SELECT g.sample_id, g.idx, g.start, g.end, g.embedding FROM sample_segments g
                JOIN samples s ON s.id = g.sample_id
                WHERE s.status = 'ok' AND s.model_version = ? AND s.root_id IN (SELECT id FROM roots WHERE transient = 0)
                  AND (g.sample_id > ? OR (g.sample_id = ? AND g.idx > ?))
                ORDER BY g.sample_id, g.idx LIMIT ?
                """, [.text(modelVersion), .int(lastID), .int(lastID), .int(lastIdx), .int(Int64(chunkSize))]) {
                ($0.int(0), $0.int(1), TimeSpan(start: $0.double(2), end: $0.double(3)), $0.blob(4))
            }
            guard let last = rows.last else { return }
            var flat: [Float] = []
            for row in rows { flat += VectorCodec.decodeFloat16(row.3) }
            body(rows.map(\.0), rows.map(\.2), flat)
            lastID = last.0; lastIdx = last.1
        }
    }

    /// Queues indexed samples whose segmentation is out of step with what they are: field recordings that were segmented by
    /// an older segmenter or not at all (indexed before field recordings were supported, or just put in the Field recording
    /// category by hand), and files that have segments but are no longer field recordings (the category was taken away).
    @discardableResult
    public func markFieldRecordingsStale() throws -> Int {
        let field = FieldRecording.sqlIs()
        let condition = """
            status = 'ok' AND ((\(field) AND segment_version < ?) OR (NOT \(field) AND segment_version > 0))
            """
        let params: [SQLValue] = [.int(Int64(FieldRecording.segmenterVersion))]
        let n = try db.scalarInt("SELECT COUNT(*) FROM samples WHERE \(condition)", params) ?? 0
        if n > 0 { try db.run("UPDATE samples SET status = 'pending' WHERE \(condition)", params) }
        return Int(n)
    }
}
