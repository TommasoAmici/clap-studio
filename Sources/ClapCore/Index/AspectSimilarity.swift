import Foundation

/// How much each quality of a sound matters when looking for similar ones.
/// With only `overall` set this is plain CLAP similarity.
public struct AspectWeights: Equatable, Sendable {
    public var overall: Double = 1       // how alike the sounds are as a whole (CLAP)
    public var brightness: Double = 0    // bright vs dark (spectral centroid)
    public var pitch: Double = 0         // same note, whatever the octave
    public var level: Double = 0         // loudness and punch
    public var length: Double = 0        // duration

    public init(overall: Double = 1, brightness: Double = 0, pitch: Double = 0, level: Double = 0, length: Double = 0) {
        self.overall = overall; self.brightness = brightness; self.pitch = pitch; self.level = level; self.length = length
    }

    public var isDefault: Bool { self == AspectWeights() }
    var total: Double { overall + brightness + pitch + level + length }
}

public enum AspectSimilarity {
    /// Each aspect is 1 for identical and 0 for very different. A missing measurement counts as neutral
    /// for the reference (so it does not skew the ranking) and as a mismatch for a candidate that lacks it.
    static func brightness(_ a: SampleRecord, _ b: SampleRecord) -> Double {
        guard let x = a.centroidHz, let y = b.centroidHz, x > 0, y > 0 else { return a.centroidHz == nil ? 0.5 : 0 }
        return 1 - min(1, abs(log2(x / y)) / 2)
    }

    static func pitch(_ a: SampleRecord, _ b: SampleRecord) -> Double {
        guard let x = a.pitchHz, x > 0 else { return 0.5 }
        guard let y = b.pitchHz, y > 0 else { return 0 }
        var semitones = abs(12 * log2(x / y)).truncatingRemainder(dividingBy: 12)
        if semitones > 6 { semitones = 12 - semitones }
        return 1 - semitones / 6
    }

    static func level(_ a: SampleRecord, _ b: SampleRecord) -> Double {
        guard let x = a.loudnessDB, let y = b.loudnessDB, let cx = a.crestDB, let cy = b.crestDB else { return a.loudnessDB == nil ? 0.5 : 0 }
        let loud = 1 - min(1, abs(x - y) / 20)
        let punch = 1 - min(1, abs(cx - cy) / 15)
        return (loud + punch) / 2
    }

    static func length(_ a: SampleRecord, _ b: SampleRecord) -> Double {
        guard a.duration > 0, b.duration > 0 else { return 0.5 }
        return 1 - min(1, abs(log2(a.duration / b.duration)) / 3)
    }

    public static func score(cosine: Float, reference: SampleRecord, other: SampleRecord, weights w: AspectWeights) -> Float {
        guard w.total > 0 else { return cosine }
        var sum = w.overall * Double(max(0, cosine))
        if w.brightness > 0 { sum += w.brightness * brightness(reference, other) }
        if w.pitch > 0 { sum += w.pitch * pitch(reference, other) }
        if w.level > 0 { sum += w.level * level(reference, other) }
        if w.length > 0 { sum += w.length * length(reference, other) }
        return Float(sum / w.total)
    }

    /// The best matches for `reference`, closest first. `lookup` supplies the records for the index's ids.
    public static func rank(reference: SampleRecord, index: VectorIndex, weights: AspectWeights, limit: Int,
                            lookup: (Int64) -> SampleRecord?) -> [(row: Int, score: Float)] {
        guard let referenceRow = index.row(forID: reference.id) else { return [] }
        if weights.isDefault {
            return index.similar(toRow: referenceRow, limit: limit).map { ($0.row, $0.score) }
        }
        let cosines = index.topK(query: index.vector(row: referenceRow), limit: index.count, excluding: referenceRow)
        var scored: [(row: Int, score: Float)] = []
        scored.reserveCapacity(cosines.count)
        for n in cosines {
            guard let other = lookup(index.ids[n.row]) else { continue }
            scored.append((n.row, score(cosine: n.score, reference: reference, other: other, weights: weights)))
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit))
    }
}
