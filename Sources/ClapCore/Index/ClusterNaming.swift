import Foundation

/// Human names for the map's clusters, from what is in them: the categories of their sounds ("Snare & Tom"),
/// told apart when several clusters would get the same name by their mood, loops vs one-shots, brightness or length
/// ("Snare · Bright", "Snare · Short").
public enum ClusterNamer {
    public struct Name: Equatable, Sendable {
        public let label: String
        /// What the cluster holds, for a tooltip: "119 sounds: 62% Snare, 21% Tom".
        public let detail: String
    }

    /// A category must make up this share of a cluster to name it alone.
    static let dominantShare = 0.5
    /// ... and this share to be named as the second half of "A & B".
    static let secondShare = 0.2
    /// A mood must be in this share of a cluster to tell it apart.
    static let moodShare = 0.3

    /// A way to tell clusters with the same base name apart. Two clusters of one name never get the same `key`.
    private struct Qualifier { let key: String; let text: String }

    /// One name per cluster that has categorised sounds (others are absent: the caller picks a fallback).
    /// `clusters[i]` is the cluster of `samples[i]`; unknown samples are skipped.
    public static func names(clusters: [Int32], samples: [SampleRecord?]) -> [Int: Name] {
        var members: [Int: [SampleRecord]] = [:]
        for (cluster, sample) in zip(clusters, samples) { if let sample { members[Int(cluster), default: []].append(sample) } }

        let brightness = terciles(samples.compactMap { $0?.centroidHz }.filter { $0 > 0 })
        let length = terciles(samples.compactMap { $0?.duration }.filter { $0 > 0 })

        var base: [Int: String] = [:], details: [Int: String] = [:], qualifiers: [Int: [Qualifier]] = [:]
        for (cluster, group) in members {
            let count = Double(group.count)
            var categories: [String: Int] = [:], moods: [String: Int] = [:]
            for s in group {
                if let c = s.effectiveCategory { categories[c, default: 0] += 1 }
                for m in s.moods { moods[m, default: 0] += 1 }
            }
            let ranked = categories.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            guard let top = ranked.first else { continue }
            if Double(top.value) / count < dominantShare, ranked.count > 1, Double(ranked[1].value) / count >= secondShare {
                base[cluster] = "\(top.key) & \(ranked[1].key)"
            } else {
                base[cluster] = top.key
            }
            let breakdown = ranked.prefix(3).map { "\(Int((Double($0.value) / count * 100).rounded()))% \($0.key)" }
            details[cluster] = "\(group.count) sound\(group.count == 1 ? "" : "s"): " + breakdown.joined(separator: ", ")

            var options: [Qualifier] = []
            if let mood = moods.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), Double(mood.value) / count >= moodShare {
                options.append(Qualifier(key: "mood:\(mood.key)", text: mood.key))
            }
            let loops = Double(group.filter { $0.isLoop == true }.count) / count
            options.append(loops >= 0.5 ? Qualifier(key: "loops", text: "Loops") : Qualifier(key: "one-shots", text: "One-shots"))
            if let b = label(median(group.compactMap(\.centroidHz).filter { $0 > 0 }), in: brightness, low: "Dark", high: "Bright") {
                options.append(Qualifier(key: "brightness:\(b)", text: b))
            }
            if let l = label(median(group.map(\.duration).filter { $0 > 0 }), in: length, low: "Short", high: "Long") {
                options.append(Qualifier(key: "length:\(l)", text: l))
            }
            qualifiers[cluster] = options
        }

        // Clusters that share a base name get a qualifier each, biggest cluster first, never the same one twice.
        var result: [Int: Name] = [:]
        for (name, sharing) in Dictionary(grouping: base.keys, by: { base[$0]! }) {
            let ordered = sharing.sorted { (members[$0]?.count ?? 0, $1) > (members[$1]?.count ?? 0, $0) }
            if ordered.count == 1 {
                result[ordered[0]] = Name(label: name, detail: details[ordered[0]] ?? "")
                continue
            }
            // A quality every one of them has (all one-shots, say) tells nothing apart.
            let keySets: [Set<String>] = ordered.map { cluster in Set((qualifiers[cluster] ?? []).map { $0.key }) }
            var used = keySets.dropFirst().reduce(keySets.first ?? []) { $0.intersection($1) }
            var usedTexts = Set<String>(), extra = 1
            for cluster in ordered {
                let text: String
                if let pick = qualifiers[cluster]?.first(where: { !used.contains($0.key) && !usedTexts.contains($0.text) }) {
                    used.insert(pick.key); usedTexts.insert(pick.text)
                    text = " · \(pick.text)"
                } else {
                    extra += 1
                    text = " #\(extra)"
                }
                result[cluster] = Name(label: name + text, detail: details[cluster] ?? "")
            }
        }
        return result
    }

    // MARK: helpers

    private static func median(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }

    /// The values that split a library into thirds, or nil when they are too few or too alike to tell apart.
    private static func terciles(_ values: [Double]) -> (low: Double, high: Double)? {
        guard values.count >= 9 else { return nil }
        let sorted = values.sorted()
        let low = sorted[sorted.count / 3], high = sorted[sorted.count * 2 / 3]
        return high > low ? (low, high) : nil
    }

    private static func label(_ value: Double?, in terciles: (low: Double, high: Double)?, low: String, high: String) -> String? {
        guard let value, let terciles else { return nil }
        if value >= terciles.high { return high }
        if value <= terciles.low { return low }
        return nil
    }
}
