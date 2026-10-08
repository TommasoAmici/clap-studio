import Foundation

/// Field recordings are long files that hold many different sounds. They are indexed in audible segments;
/// the sample's own embedding is the composite of the segment embeddings.
public enum FieldRecording {
    /// Files at least this long (seconds) are field recordings.
    public static let minimumSeconds = 30.0
    /// Bump when segmentation changes so existing field recordings are re-indexed.
    public static let segmenterVersion = 1
    /// Name of the automatic category.
    public static let categoryName = "Field recording"

    public static func isFieldRecording(duration: Double) -> Bool { duration >= minimumSeconds }

    /// Length-weighted mean of the segment embeddings, L2-normalised. Long events count for more.
    public static func composite(_ segments: [SegmentEmbedding]) -> [Float] {
        guard let dim = segments.first?.embedding.count else { return [] }
        var sum = [Double](repeating: 0, count: dim)
        for s in segments where s.embedding.count == dim {
            let w = max(s.length, 0.01)
            for i in 0..<dim { sum[i] += Double(s.embedding[i]) * w }
        }
        let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return sum.map { Float($0) } }
        return sum.map { Float($0 / norm) }
    }

    /// Descriptors of the whole recording from those of its segments: loudest peak, power-averaged loudness and
    /// energy-weighted brightness. Tempo, key and pitch mean nothing across unrelated sounds, so they stay empty.
    public static func aggregate(_ parts: [(descriptors: SoundDescriptors, seconds: Double)]) -> SoundDescriptors {
        let audible = parts.filter { $0.descriptors.loudnessDB > -119 }
        guard !audible.isEmpty else {
            return SoundDescriptors(loudnessDB: -120, peakDB: -120, crestDB: 0, centroidHz: 0, isLoop: false)
        }
        var power = 0.0, seconds = 0.0, centroid = 0.0, centroidWeight = 0.0
        var peak = -Double.infinity
        for (d, length) in audible {
            let p = pow(10, d.loudnessDB / 10) * length
            power += p; seconds += length
            centroid += d.centroidHz * p; centroidWeight += p
            peak = max(peak, d.peakDB)
        }
        let loudness = 10 * log10(max(power / max(seconds, 1e-9), 1e-12))
        return SoundDescriptors(loudnessDB: loudness, peakDB: peak, crestDB: peak - loudness,
                                centroidHz: centroidWeight > 0 ? centroid / centroidWeight : 0, isLoop: false)
    }
}
