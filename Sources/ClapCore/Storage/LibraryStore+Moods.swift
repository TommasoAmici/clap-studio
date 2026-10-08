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
        try forEachEmbeddingChunk(modelVersion: ClapEmbedder.versionTag) { chunkIDs, flat, count in
            ids += chunkIDs
            raw += scorer.rawScores(flat: flat, count: count)
        }
        let assignments = scorer.assign(raw: raw, count: ids.count)
        try db.transaction {
            try db.run("DELETE FROM sample_moods", [])
            for (id, moods) in zip(ids, assignments) {
                for mood in moods {
                    try db.run("INSERT INTO sample_moods(sample_id, mood, z) VALUES(?, ?, ?)",
                               [.int(id), .text(scorer.names[mood.mood]), .double(Double(mood.z))])
                }
            }
        }
        try setMeta("mood_state", state)
        return ids.count
    }
}
