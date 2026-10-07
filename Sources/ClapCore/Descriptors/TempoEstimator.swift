import Foundation

/// Tempo from an onset-strength envelope (autocorrelation with a mild preference for 120 BPM).
enum TempoEstimator {
    struct Result { var bpm: Double; var confidence: Double; var onsetCount: Int }

    /// - Parameters:
    ///   - flux: onset strength per frame.
    ///   - frameRate: frames per second.
    ///   - wholeFileSeconds: length of the file when all of it was analysed, else nil.
    static func estimate(flux: [Float], frameRate: Double, wholeFileSeconds: Double?) -> Result? {
        let n = flux.count
        guard n > 16 else { return nil }
        let mean = flux.reduce(0, +) / Float(n)
        let x = flux.map { $0 - mean }
        let energy = x.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-9 else { return nil }

        let minLag = max(2, Int(frameRate * 60 / 200)), maxLag = min(n / 2, Int(frameRate * 60 / 60))
        guard minLag < maxLag else { return nil }
        var r = [Double](repeating: 0, count: maxLag + 2)
        for lag in (minLag - 1)...(maxLag + 1) where lag < n {
            var sum: Float = 0
            for t in 0..<(n - lag) { sum += x[t] * x[t + lag] }
            r[lag] = Double(sum / energy)
        }

        var best = minLag, bestScore = -Double.infinity
        for lag in minLag...maxLag {
            guard r[lag] >= r[lag - 1], r[lag] >= r[lag + 1] else { continue }   // local peak
            let bpm = 60 * frameRate / Double(lag)
            let score = r[lag] * exp(-0.5 * pow(log2(bpm / 120) / 0.8, 2))
            if score > bestScore { bestScore = score; best = lag }
        }
        guard bestScore.isFinite else { return nil }

        // Parabolic interpolation for sub-frame lag precision.
        let a = r[best - 1], b = r[best], c = r[best + 1]
        let denom = a - 2 * b + c
        let lag = Double(best) + (denom == 0 ? 0 : 0.5 * (a - c) / denom)
        var bpm = 60 * frameRate / lag
        let confidence = max(0, min(1, r[best]))

        if let seconds = wholeFileSeconds, seconds > 1 {
            // Loops are usually whole bars: if the estimate agrees with a bar-based tempo, use the exact one.
            for beats in [2.0, 4, 8, 16, 32, 64] {
                let candidate = 60 * beats / seconds
                guard candidate >= 70, candidate <= 180 else { continue }
                for ratio in [1.0, 2, 0.5] where abs(candidate * ratio - bpm) / bpm < 0.04 {
                    bpm = candidate
                }
            }
        }
        return Result(bpm: bpm, confidence: confidence, onsetCount: countPeaks(flux))
    }

    private static func countPeaks(_ flux: [Float]) -> Int {
        let mean = flux.reduce(0, +) / Float(flux.count)
        let sd = sqrtf(flux.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(flux.count))
        let threshold = mean + 1.5 * sd
        var count = 0, i = 1
        while i < flux.count - 1 {
            if flux[i] > threshold, flux[i] >= flux[i - 1], flux[i] >= flux[i + 1] { count += 1; i += 3 } else { i += 1 }
        }
        return count
    }
}
