import Foundation

/// "Like this, but darker, no reverb": words that adjust a search by example.
///
/// The sound and each phrase give every sample a similarity. They are put on one scale (standard scores across
/// the library, since audio-to-audio and text-to-audio similarities sit at different levels) and combined:
/// what the user asked for adds, what they ruled out subtracts.
public struct QueryRefinement: Equatable, Sendable {
    public var positives: [String] = []
    public var negatives: [String] = []

    public var isEmpty: Bool { positives.isEmpty && negatives.isEmpty }
    /// Every phrase that needs a text embedding.
    public var phrases: [String] { positives + negatives }

    public init(positives: [String] = [], negatives: [String] = []) { self.positives = positives; self.negatives = negatives }

    static let negativePrefixes = ["not ", "no ", "less ", "fewer ", "without ", "minus ", "-"]
    static let positivePrefixes = ["more ", "with ", "plus ", "add ", "but ", "and ", "+"]

    /// Splits at commas, semicolons and "but". A phrase starting with "no", "not", "less", "without" or "-" is ruled out;
    /// "more" and "with" are dropped (they add nothing to what is searched for).
    public static func parse(_ text: String) -> QueryRefinement {
        var parts = [text]
        for separator in [",", ";", "\n"] { parts = parts.flatMap { $0.components(separatedBy: separator) } }
        parts = parts.flatMap { $0.components(separatedBy: " but ") }
        var result = QueryRefinement()
        for raw in parts {
            var phrase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            var negative = false
            // Prefixes can stack ("but no reverb"), so strip until none is left.
            var changed = true
            while changed {
                changed = false
                let lower = phrase.lowercased()
                if let prefix = negativePrefixes.first(where: { lower.hasPrefix($0) }) {
                    phrase = String(phrase.dropFirst(prefix.count)); negative.toggle(); changed = true
                } else if let prefix = positivePrefixes.first(where: { lower.hasPrefix($0) }) {
                    phrase = String(phrase.dropFirst(prefix.count)); changed = true
                }
                phrase = phrase.trimmingCharacters(in: .whitespaces)
            }
            guard !phrase.isEmpty else { continue }
            if negative { result.negatives.append(phrase) } else { result.positives.append(phrase) }
        }
        return result
    }

    /// How much the words count against the sound they adjust.
    public static let defaultWeight: Float = 0.5
    /// Words re-rank the sounds nearest the original; they do not bring in sounds that are nothing like it.
    public static let defaultCandidates = 300

    /// Standard scores: each value's distance from the mean in standard deviations, so scores from different
    /// sources can be added.
    static func standardised(_ scores: [Int64: Float]) -> [Int64: Float] {
        guard scores.count > 1 else { return scores.mapValues { _ in 0 } }
        let n = Float(scores.count)
        let mean = scores.values.reduce(0, +) / n
        let variance = scores.values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let deviation = max(variance.squareRoot(), 1e-6)
        return scores.mapValues { ($0 - mean) / deviation }
    }

    /// The sound's similarity with the phrases added and subtracted. Only samples that have a similarity to the sound
    /// are ranked, and only the `candidates` nearest the sound; a phrase a sample has no score for counts as average.
    public static func combine(base: [Int64: Float], positives: [[Int64: Float]], negatives: [[Int64: Float]],
                               weight: Float = defaultWeight, candidates: Int = defaultCandidates) -> [Int64: Float] {
        var combined = standardised(base)
        if combined.count > candidates {
            let keep = Set(combined.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(candidates).map(\.key))
            combined = combined.filter { keep.contains($0.key) }
        }
        for phrase in positives {
            for (id, z) in standardised(phrase) where combined[id] != nil { combined[id]! += weight * z }
        }
        for phrase in negatives {
            for (id, z) in standardised(phrase) where combined[id] != nil { combined[id]! -= weight * z }
        }
        return combined
    }
}
