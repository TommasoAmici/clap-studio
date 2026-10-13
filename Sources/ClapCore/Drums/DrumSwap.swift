import Foundation

/// How far from the current sound a swap may reach.
public enum DrumVariation: String, CaseIterable, Identifiable, Sendable, Codable {
    case close = "Close", medium = "Medium", wide = "Wide"
    public var id: String { rawValue }
    /// How many of the nearest sounds a swap picks among.
    public var spread: Int {
        switch self {
        case .close: return 4
        case .medium: return 12
        case .wide: return 40
        }
    }
}

/// Finds a replacement for a drum sound: something that fills the same role (category, one-shot or loop) and
/// sounds close to what it replaces, not one of the sounds the kit already uses.
public enum DrumSwap {
    /// How many neighbours are read from the index before the role filter, so a rare category still has candidates.
    static let reach = 600

    /// Sounds that could take `reference`'s place, nearest first.
    public static func candidates(for reference: SampleRecord, index: VectorIndex?, weights: AspectWeights = AspectWeights(),
                                  samples: [SampleRecord], lookup: (Int64) -> SampleRecord?,
                                  excluding used: Set<Int64>) -> [Int64] {
        func fits(_ s: SampleRecord) -> Bool {
            s.id != reference.id && !used.contains(s.id) && !s.hidden && s.status == .ok && !s.isFieldRecording
                && s.effectiveCategory == reference.effectiveCategory && (s.isLoop ?? false) == (reference.isLoop ?? false)
        }
        if let index, index.row(forID: reference.id) != nil {
            let ranked = AspectSimilarity.rank(reference: reference, index: index, weights: weights, limit: min(reach, index.count)) { lookup($0) }
            let near = ranked.compactMap { hit -> Int64? in
                let id = index.ids[hit.row]
                guard let sample = lookup(id), fits(sample) else { return nil }
                return id
            }
            if !near.isEmpty { return near }
        }
        // Not analysed yet (or nothing close): anything that fills the role, in a stable order.
        return samples.filter(fits).map(\.id).sorted()
    }

    /// One of the first `spread` candidates, chosen at random. nil when there are none.
    public static func pick(from candidates: [Int64], spread: Int, using generator: inout some RandomNumberGenerator) -> Int64? {
        let pool = candidates.prefix(max(1, spread))
        return pool.randomElement(using: &generator)
    }

    /// The sound to try on a track: a close one, skipping what the track just had so repeated swaps keep moving.
    public static func next(for reference: SampleRecord, history: [Int64], spread: Int, index: VectorIndex?, weights: AspectWeights = AspectWeights(),
                            samples: [SampleRecord], lookup: (Int64) -> SampleRecord?, excluding used: Set<Int64>,
                            using generator: inout some RandomNumberGenerator) -> Int64? {
        let all = candidates(for: reference, index: index, weights: weights, samples: samples, lookup: lookup,
                             excluding: used.union(history))
        // When the recent sounds have used everything up, allow them again rather than doing nothing.
        let list = all.isEmpty ? candidates(for: reference, index: index, weights: weights, samples: samples, lookup: lookup, excluding: used) : all
        return pick(from: list, spread: spread, using: &generator)
    }
}
