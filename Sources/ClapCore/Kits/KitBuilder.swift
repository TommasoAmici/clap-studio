import Foundation

/// One position in a drum kit, with the samples that could fill it, best fit first.
public struct KitSlot: Identifiable, Sendable, Equatable {
    public let category: String
    public let candidates: [Int64]
    /// True for the sample the kit was built around; it has no alternatives.
    public let isAnchor: Bool
    public var id: String { category }
}

/// Suggests the rest of a kit around one sample: sounds from other drum categories that share its character
/// (CLAP similarity), sit at a compatible level, and, when the library is organised in packs, come from the same pack.
public enum KitBuilder {
    public static let defaultCategories = ["Kick", "Snare", "Clap", "Hi-hat", "Cymbal", "Tom", "Percussion"]

    public static func suggest(anchor: SampleRecord, samples: [SampleRecord], index: VectorIndex,
                               categories: [String] = defaultCategories, perSlot: Int = 12) -> [KitSlot] {
        guard let anchorRow = index.row(forID: anchor.id) else { return [] }
        let anchorVector = index.vector(row: anchorRow)
        let cosines = index.topK(query: anchorVector, limit: index.count)
        var cosine: [Int64: Float] = [:]
        for n in cosines { cosine[index.ids[n.row]] = n.score }

        let anchorCategory = anchor.effectiveCategory
        var slots: [KitSlot] = []
        for category in categories {
            if category == anchorCategory {
                slots.append(KitSlot(category: category, candidates: [anchor.id], isAnchor: true))
                continue
            }
            let ranked = samples
                .filter { $0.effectiveCategory == category && !$0.hidden && $0.status == .ok && $0.isLoop != true && $0.id != anchor.id }
                .compactMap { s -> (id: Int64, score: Float)? in
                    guard let c = cosine[s.id] else { return nil }
                    return (s.id, score(cosine: c, anchor: anchor, candidate: s))
                }
                .sorted { $0.score > $1.score }
                .prefix(perSlot)
            if !ranked.isEmpty { slots.append(KitSlot(category: category, candidates: ranked.map(\.id), isAnchor: false)) }
        }
        // An anchor outside the listed categories still belongs in its own kit.
        if let anchorCategory, !categories.contains(anchorCategory) {
            slots.insert(KitSlot(category: anchorCategory, candidates: [anchor.id], isAnchor: true), at: 0)
        } else if anchorCategory == nil {
            slots.insert(KitSlot(category: "Anchor", candidates: [anchor.id], isAnchor: true), at: 0)
        }
        return slots
    }

    static func score(cosine: Float, anchor: SampleRecord, candidate: SampleRecord) -> Float {
        var level: Float = 0.5
        if let a = anchor.loudnessDB, let c = candidate.loudnessDB { level = Float(1 - min(1, abs(a - c) / 12)) }
        var pack: Float = 0
        if anchor.rootID == candidate.rootID {
            if anchor.folder == candidate.folder { pack = 0.15 }
            else if topFolder(anchor) == topFolder(candidate), !topFolder(anchor).isEmpty { pack = 0.08 }
        }
        return 0.65 * max(0, cosine) + 0.25 * level + pack
    }

    private static func topFolder(_ s: SampleRecord) -> String { s.folder.split(separator: "/").first.map(String.init) ?? "" }
}
