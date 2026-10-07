import Foundation

/// Fundamental pitch (YIN) for tonal one-shots and musical key (chroma profiles) for loops.
enum PitchKeyEstimator {
    /// Pitch in Hz of the sound around `center`, or nil when it is noisy / unpitched.
    static func pitch(signal: [Float], sampleRate: Double, center: Int) -> Double? {
        let window = 2048
        let maxLag = min(Int(sampleRate / 30), 2400), minLag = max(2, Int(sampleRate / 2000))
        let start = max(0, min(center, signal.count - window - maxLag - 1))
        guard start >= 0, signal.count > window + maxLag + 1, maxLag > minLag else { return nil }

        var diff = [Float](repeating: 0, count: maxLag + 1)
        signal.withUnsafeBufferPointer { s in
            for tau in 1...maxLag {
                var sum: Float = 0
                for j in 0..<window { let d = s[start + j] - s[start + j + tau]; sum += d * d }
                diff[tau] = sum
            }
        }
        // Cumulative mean normalised difference.
        var cmnd = [Float](repeating: 1, count: maxLag + 1)
        var running: Float = 0
        for tau in 1...maxLag {
            running += diff[tau]
            cmnd[tau] = running > 0 ? diff[tau] * Float(tau) / running : 1
        }
        var tau = minLag
        while tau < maxLag {
            if cmnd[tau] < 0.15 {
                while tau + 1 < maxLag, cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                let a = cmnd[tau - 1], b = cmnd[tau], c = cmnd[tau + 1]
                let denom = a - 2 * b + c
                let refined = Double(tau) + (denom == 0 ? 0 : Double(0.5 * (a - c) / denom))
                return sampleRate / refined
            }
            tau += 1
        }
        return nil
    }

    private static let major: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minor: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Best-matching key ("A minor") for a 12-bin chroma vector, or nil when no key stands out.
    static func key(chroma: [Double]) -> String? {
        guard chroma.count == 12, chroma.reduce(0, +) > 0 else { return nil }
        func correlation(_ profile: [Double], shift: Int) -> Double {
            let rotated = (0..<12).map { chroma[($0 + shift) % 12] }
            let mc = rotated.reduce(0, +) / 12, mp = profile.reduce(0, +) / 12
            var num = 0.0, dc = 0.0, dp = 0.0
            for i in 0..<12 {
                num += (rotated[i] - mc) * (profile[i] - mp)
                dc += (rotated[i] - mc) * (rotated[i] - mc)
                dp += (profile[i] - mp) * (profile[i] - mp)
            }
            return dc > 0 ? num / sqrt(dc * dp) : 0
        }
        var best: (score: Double, name: String)?
        for tonic in 0..<12 {
            for (profile, mode) in [(major, "major"), (minor, "minor")] {
                let score = correlation(profile, shift: tonic)
                if score > (best?.score ?? -2) { best = (score, "\(NoteNames.sharps[tonic]) \(mode)") }
            }
        }
        guard let best, best.score > 0.6 else { return nil }
        return best.name
    }
}
