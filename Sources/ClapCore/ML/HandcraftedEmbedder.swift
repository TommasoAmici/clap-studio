import Foundation

/// Fallback embedding from classic spectral and envelope statistics. No model needed.
public struct HandcraftedEmbedder: EmbeddingProvider {
    public let version = "handcrafted-v2"
    public var dimension: Int { MelSpectrogram.nMels * 3 + 8 }

    public init() {}

    public func embed(_ mel: MelSpectrogram) throws -> [Float] {
        let bands = MelSpectrogram.nMels
        let n = max(1, mel.validFrames)
        var out = [Float]()
        out.reserveCapacity(dimension)

        // Per-band statistics over the valid frames (dB scaled to roughly [-1, 1]).
        var bandMean = [Float](repeating: 0, count: bands)
        var bandStd = bandMean, bandMax = [Float](repeating: -100, count: bands)
        for t in 0..<n {
            for b in 0..<bands {
                let v = mel.values[t * bands + b]
                bandMean[b] += v
                bandMax[b] = max(bandMax[b], v)
            }
        }
        for b in 0..<bands { bandMean[b] /= Float(n) }
        for t in 0..<n {
            for b in 0..<bands {
                let d = mel.values[t * bands + b] - bandMean[b]
                bandStd[b] += d * d
            }
        }
        for b in 0..<bands { bandStd[b] = sqrtf(bandStd[b] / Float(n)) }
        out += bandMean.map { $0 / 50 }
        out += bandStd.map { $0 / 25 }
        out += bandMax.map { $0 / 50 }

        // Temporal envelope and spectral shape.
        var energy = [Float](repeating: 0, count: n)
        var centroid = [Float](repeating: 0, count: n)
        var flatness = [Float](repeating: 0, count: n)
        for t in 0..<n {
            var sum: Float = 0, weighted: Float = 0, logSum: Float = 0
            for b in 0..<bands {
                let p = powf(10, mel.values[t * bands + b] / 10)
                sum += p
                weighted += p * Float(b)
                logSum += logf(max(p, 1e-12))
            }
            energy[t] = 10 * log10f(max(sum, 1e-12))
            centroid[t] = sum > 1e-12 ? weighted / sum / Float(bands) : 0
            flatness[t] = sum > 1e-12 ? expf(logSum / Float(bands)) / (sum / Float(bands)) : 0
        }
        let peakIndex = energy.enumerated().max { $0.element < $1.element }?.offset ?? 0
        let peak = energy[peakIndex]
        var decay = n - peakIndex
        for t in peakIndex..<n where energy[t] < peak - 30 { decay = t - peakIndex; break }
        let secondsPerFrame = Float(LogMelExtractor.hop) / Float(LogMelExtractor.sampleRate)
        let meanCentroid = centroid.reduce(0, +) / Float(n)
        let centroidStd = sqrtf(centroid.reduce(0) { $0 + ($1 - meanCentroid) * ($1 - meanCentroid) } / Float(n))
        out.append(Float(peakIndex) * secondsPerFrame)                  // attack time
        out.append(log10f(1 + Float(decay) * secondsPerFrame * 100) / 2) // decay time (log)
        out.append(log10f(1 + Float(mel.validSeconds) * 100) / 2)        // duration (log)
        out.append(meanCentroid * 2)
        out.append(centroidStd * 4)
        out.append(flatness.reduce(0, +) / Float(n))
        out.append(peak / 50)
        out.append((energy[n - 1] - peak) / 100)
        return out
    }
}
