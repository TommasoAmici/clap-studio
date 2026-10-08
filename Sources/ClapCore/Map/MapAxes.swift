import Foundation

/// A measured property that can be used as a map axis or to colour the dots.
public enum MapProperty: String, CaseIterable, Sendable, Identifiable {
    case brightness = "Brightness", loudness = "Loudness", punch = "Punch", length = "Length", tempo = "Tempo", pitch = "Pitch"
    public var id: String { rawValue }

    /// The value for a sample, or nil when it has not been measured (a one-shot has no tempo).
    public func value(of s: SampleRecord) -> Double? {
        switch self {
        case .brightness: return s.centroidHz.flatMap { $0 > 0 ? log2($0) : nil }
        case .loudness: return s.loudnessDB.flatMap { $0 > -90 ? $0 : nil }
        case .punch: return s.crestDB
        case .length: return s.duration > 0 ? log2(s.duration) : nil
        case .tempo: return s.isLoop == true ? s.effectiveBPM : nil
        case .pitch: return s.pitchHz.flatMap { $0 > 0 ? log2($0) : nil }
        }
    }
}

public enum MapAxes {
    public struct Layout: Sendable {
        /// Interleaved x, y per requested sample, in the same units as the similarity map.
        public var xy: [Float]
        /// False where a sample has no value on one of the axes (it is left off the map).
        public var valid: [Bool]
    }

    /// Places samples by two properties. Values are spread by rank, so a few extreme sounds do not squash
    /// the rest into a corner, and ties are nudged apart deterministically so they stay individually visible.
    public static func layout(_ samples: [SampleRecord?], x: MapProperty, y: MapProperty, extent: Float = 10) -> Layout {
        let xs = ranks(samples.map { $0.flatMap(x.value) })
        let ys = ranks(samples.map { $0.flatMap(y.value) })
        var xy = [Float](repeating: 0, count: samples.count * 2)
        var valid = [Bool](repeating: false, count: samples.count)
        for (i, sample) in samples.enumerated() {
            guard let sample, let rx = xs[i], let ry = ys[i] else { continue }
            let jitter = Self.jitter(sample.id)
            xy[i * 2] = (rx * 2 - 1) * extent + jitter.0 * extent * 0.01
            xy[i * 2 + 1] = (ry * 2 - 1) * extent + jitter.1 * extent * 0.01
            valid[i] = true
        }
        return Layout(xy: xy, valid: valid)
    }

    /// Rank of each value in 0...1 (nil stays nil); equal values share their average rank.
    static func ranks(_ values: [Double?]) -> [Float?] {
        let present = values.enumerated().compactMap { i, v in v.map { (i, $0) } }.sorted { $0.1 < $1.1 }
        var result = [Float?](repeating: nil, count: values.count)
        guard present.count > 1 else { present.forEach { result[$0.0] = 0.5 }; return result }
        var start = 0
        while start < present.count {
            var end = start
            while end + 1 < present.count, present[end + 1].1 == present[start].1 { end += 1 }
            let rank = Float(start + end) / 2 / Float(present.count - 1)
            for k in start...end { result[present[k].0] = rank }
            start = end + 1
        }
        return result
    }

    private static func jitter(_ id: Int64) -> (Float, Float) {
        var h = UInt64(bitPattern: id) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        let a = Float(h & 0xFFFF) / 65535 - 0.5
        let b = Float((h >> 16) & 0xFFFF) / 65535 - 0.5
        return (a, b)
    }

    /// Bin 0..<bins for a value within the observed range (used to colour dots along a gradient).
    public static func bin(_ value: Double, low: Double, high: Double, bins: Int) -> Int {
        guard high > low else { return 0 }
        return min(bins - 1, max(0, Int((value - low) / (high - low) * Double(bins))))
    }
}
