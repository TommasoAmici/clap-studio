import Foundation

/// A sound heard in a field recording (birds, water, ...) and where.
public struct SoundOccurrence: Sendable, Equatable {
    public let name: String
    public let spans: [TimeSpan]
    public var total: Double { spans.reduce(0) { $0 + $1.length } }
}

/// Persistence of the sounds named in field recordings. Like moods, they are recomputed for every recording
/// whenever its segments or the vocabulary change (a few matrix products), so the work is not cancellable.
extension LibraryStore {
    /// Segments shorter than this are too brief to name.
    static let minimumLabelledSeconds = 1.0
    /// Two stretches of the same sound closer than this are shown as one.
    static let mergeGapSeconds = 0.5

    static var soundsTag: String { "\(ClapEmbedder.versionTag)/\(SoundCategories.soundsVersion)" }

    /// Identifies what the stored labels were computed from: vocabulary, model, and the segments that exist.
    private func soundsState() -> String {
        let rows = (try? db.query("""
            SELECT COUNT(*), MAX(s.indexed_at) FROM sample_segments g JOIN samples s ON s.id = g.sample_id
            WHERE s.status = 'ok' AND s.model_version = ?
            """, [.text(ClapEmbedder.versionTag)]) { ($0.int(0), $0.isNull(1) ? 0 : $0.double(1)) }) ?? []
        let (count, newest) = rows.first ?? (0, 0)
        return "\(Self.soundsTag)/\(count)/\(Int(newest))"
    }

    /// Labels are missing or were computed from other segments, phrases or models.
    public func soundsAreStale() -> Bool { meta("sounds_state") != soundsState() }

    /// Names the sounds of every field recording's segments. `categorizer` must be built over
    /// `SoundCategories.segmentVocabulary`.
    @discardableResult
    public func labelSegments(with categorizer: Categorizer, limit: Int = 2, minimum: Float = 0.2) throws -> Int {
        let state = soundsState()
        var rows: [(id: Int64, idx: Int64, label: Categorizer.Label)] = []
        var next: [Int64: Int64] = [:]
        try forEachSegmentChunk(modelVersion: ClapEmbedder.versionTag) { ids, spans, flat in
            let labels = categorizer.classifyTop(flat: flat, count: ids.count, limit: limit, minimum: minimum)
            for (i, id) in ids.enumerated() {
                let idx = next[id, default: 0]
                next[id] = idx + 1
                guard spans[i].length >= Self.minimumLabelledSeconds, i < labels.count else { continue }
                rows += labels[i].map { (id: id, idx: idx, label: $0) }
            }
        }
        try db.transaction {
            try db.run("DELETE FROM segment_sounds", [])
            for row in rows {
                try db.run("INSERT INTO segment_sounds(sample_id, idx, sound, score) VALUES(?, ?, ?, ?)",
                           [.int(row.id), .int(row.idx), .text(row.label.name), .double(Double(row.label.confidence))])
            }
        }
        try setMeta("sounds_state", state)
        return next.count
    }

    /// The sounds of one recording, longest first, each with where it occurs (neighbouring stretches merged).
    public func soundOccurrences(sampleID: Int64) -> [SoundOccurrence] {
        let rows = (try? db.query("""
            SELECT n.sound, g.start, g.end FROM segment_sounds n
            JOIN sample_segments g ON g.sample_id = n.sample_id AND g.idx = n.idx
            WHERE n.sample_id = ? ORDER BY n.sound, g.start
            """, [.int(sampleID)]) { ($0.text(0), TimeSpan(start: $0.double(1), end: $0.double(2))) }) ?? []
        var spansByName: [String: [TimeSpan]] = [:]
        for (name, span) in rows {
            if var last = spansByName[name]?.last, span.start - last.end <= Self.mergeGapSeconds {
                last.end = max(last.end, span.end)
                spansByName[name]![spansByName[name]!.count - 1] = last
            } else {
                spansByName[name, default: []].append(span)
            }
        }
        return spansByName.map { SoundOccurrence(name: $0.key, spans: $0.value) }
            .sorted { ($0.total, $1.name) > ($1.total, $0.name) }
    }
}
