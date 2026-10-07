import Foundation

public struct ReuseSuggestion: Identifiable, Sendable, Equatable {
    public struct Alternative: Sendable, Equatable {
        public let id: Int64
        public let score: Float
    }
    /// The sample you keep reaching for.
    public let favoriteID: Int64
    public let uses: Int
    /// Sounds close to it that you have never grabbed, closest first.
    public let alternatives: [Alternative]
    public var id: Int64 { favoriteID }
}

/// Points out the samples you use over and over, and similar ones you have not tried.
public enum ReuseInsights {
    /// - Parameters:
    ///   - samples: the library (hidden and unavailable samples are ignored).
    ///   - index: the similarity index the neighbours come from.
    ///   - favorites: how many of the most-used samples to report on.
    ///   - perSample: alternatives to list for each.
    public static func suggestions(samples: [SampleRecord], index: VectorIndex, favorites: Int = 12,
                                   perSample: Int = 5, pool: Int = 80) -> [ReuseSuggestion] {
        let usable = Dictionary(uniqueKeysWithValues: samples.filter { $0.status == .ok && !$0.hidden }.map { ($0.id, $0) })
        let mostUsed = usable.values.filter { $0.useCount > 0 }
            .sorted { ($0.useCount, $1.id) > ($1.useCount, $0.id) }.prefix(favorites)
        return mostUsed.compactMap { sample in
            guard let row = index.row(forID: sample.id) else { return nil }
            let fresh = index.similar(toRow: row, limit: pool).compactMap { n -> ReuseSuggestion.Alternative? in
                let id = index.ids[n.row]
                guard let other = usable[id], other.useCount == 0 else { return nil }
                return .init(id: id, score: n.score)
            }
            guard !fresh.isEmpty else { return nil }
            return ReuseSuggestion(favoriteID: sample.id, uses: sample.useCount, alternatives: Array(fresh.prefix(perSample)))
        }
    }
}
