import Foundation

/// Persistence of moods. A mood is judged against the whole library, so adding or changing samples can change the
/// moods of every sample: they are recomputed (a single matrix product) whenever the set of embeddings changes.
extension LibraryStore {
    static var moodTag: String { "\(ClapEmbedder.versionTag)/\(SoundMoods.version)" }

    /// Identifies the embeddings the stored moods were computed from: how many there are and when the newest was made.
    private func moodState() -> String {
        let rows = (try? db.query("SELECT COUNT(*), MAX(indexed_at) FROM samples WHERE \(Self.embeddedFilter)",
                                  [.text(ClapEmbedder.versionTag)]) { ($0.int(0), $0.isNull(1) ? 0 : $0.double(1)) }) ?? []
        let (count, newest) = rows.first ?? (0, 0)
        return "\(Self.moodTag)/\(count)/\(Int(newest))"
    }

    /// Moods are missing or were computed from other embeddings, phrases or models.
    public func moodsAreStale() -> Bool { meta("mood_state") != moodState() }

    /// Recomputes the moods of every library sample. Cheap, so it is not cancellable.
    @discardableResult
    public func assignMoods(with scorer: MoodScorer) throws -> Int {
        let state = moodState()
        var ids: [Int64] = [], raw: [Float] = []
        // Regular samples set the standard. A recording's composite embedding is an average of unrelated sounds, so
        // field recordings are judged by their segments instead, against that same standard.
        try forEachEmbeddingChunk(modelVersion: ClapEmbedder.versionTag, excludingFieldRecordings: true) { chunkIDs, flat, count in
            ids += chunkIDs
            raw += scorer.rawScores(flat: flat, count: count)
        }
        let assignments = scorer.assign(raw: raw, count: ids.count)
        var rows: [(id: Int64, mood: Int, z: Float)] = []
        for (id, moods) in zip(ids, assignments) { rows += moods.map { (id: id, mood: $0.mood, z: $0.z) } }
        if ids.count >= SoundMoods.minimumLibrary {
            rows += try fieldRecordingMoods(scorer: scorer, against: scorer.statistics(raw: raw, count: ids.count))
        }
        try db.transaction {
            try db.run("DELETE FROM sample_moods", [])
            for row in rows {
                try db.run("INSERT INTO sample_moods(sample_id, mood, z) VALUES(?, ?, ?)",
                           [.int(row.id), .text(scorer.names[row.mood]), .double(Double(row.z))])
            }
        }
        try setMeta("mood_state", state)
        return ids.count
    }

    /// Every mood that any segment of a field recording has, with the best z among its segments.
    /// Not capped per file: a long recording can well be dark in one place and happy in another.
    func fieldRecordingMoods(scorer: MoodScorer, against stats: MoodScorer.Statistics) throws -> [(id: Int64, mood: Int, z: Float)] {
        var best: [Int64: [Int: Float]] = [:]
        try forEachSegmentChunk(modelVersion: ClapEmbedder.versionTag) { ids, _, flat in
            let raw = scorer.rawScores(flat: flat, count: ids.count)
            for (id, moods) in zip(ids, scorer.assign(raw: raw, count: ids.count, against: stats)) {
                for m in moods { best[id, default: [:]][m.mood] = max(best[id]?[m.mood] ?? -.infinity, m.z) }
            }
        }
        return best.sorted { $0.key < $1.key }.flatMap { id, moods in
            moods.sorted { $0.key < $1.key }.map { (id: id, mood: $0.key, z: $0.value) }
        }
    }

    /// The user's own moods for several samples at once (nil goes back to the automatic ones, an empty list means
    /// none). The automatic moods are kept, since they are recomputed on their own.
    public func setManualMoods(_ values: [(id: Int64, moods: [String]?)]) throws {
        try db.transaction {
            for value in values {
                let text: SQLValue = value.moods.map { .text(SoundMoods.sorted($0).joined(separator: "\u{1F}")) } ?? .null
                try db.run("UPDATE samples SET moods_manual = ? WHERE id = ?", [text, .int(value.id)])
            }
        }
    }
}
