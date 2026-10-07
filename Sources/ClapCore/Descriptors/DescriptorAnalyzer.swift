import Foundation

/// Computes `SoundDescriptors` from decoded mono audio. Not thread-safe: one analyzer per worker.
public final class DescriptorAnalyzer {
    private static let nFFT = 2048
    private static let hop = 512
    private let spectrum = SpectrumAnalyzer(nFFT: DescriptorAnalyzer.nFFT)

    public init() {}

    /// - Parameters:
    ///   - samples: mono audio (the start of the file, at most the analysis window).
    ///   - fileDuration: length of the whole file in seconds.
    public func analyze(samples: [Float], sampleRate: Double, fileDuration: Double) -> SoundDescriptors {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 1e-6 else {
            return SoundDescriptors(loudnessDB: -120, peakDB: -120, crestDB: 0, centroidHz: 0, isLoop: false)
        }
        let peakDB = 20 * log10(Double(peak))
        let loudness = Self.activeLoudness(samples, peak: peak)

        // One pass over the spectrum: brightness, onset strength and chroma.
        let n = Self.nFFT, hop = Self.hop, bins = spectrum.bins
        let frameCount = max(1, (samples.count - 1) / hop + 1)
        var magnitudes = [Float](repeating: 0, count: bins), previous = magnitudes
        var flux = [Float](repeating: 0, count: frameCount), energy = [Float](repeating: 0, count: frameCount)
        var centroids = [Float](repeating: 0, count: frameCount)
        var chroma = [Double](repeating: 0, count: 12)
        let binHz = sampleRate / Double(n)
        let chromaBins = (Int(65 / binHz) + 1)..<min(bins, Int(2_000 / binHz))
        let chromaClass: [Int] = chromaBins.map { k in
            ((Int((69 + 12 * log2(Double(k) * binHz / 440)).rounded()) % 12) + 12) % 12
        }

        for t in 0..<frameCount {
            spectrum.magnitudes(of: samples, start: t * hop - n / 2, into: &magnitudes)
            var total: Float = 0, weighted: Float = 0, rise: Float = 0
            for k in 0..<bins {
                let m = magnitudes[k]
                total += m; weighted += m * Float(k)
                rise += max(0, m - previous[k])
            }
            energy[t] = total
            centroids[t] = total > 0 ? weighted / total * Float(binHz) : 0
            flux[t] = rise
            for (i, k) in chromaBins.enumerated() { chroma[chromaClass[i]] += Double(magnitudes[k]) }
            swap(&magnitudes, &previous)
        }

        let maxEnergy = energy.max() ?? 0
        var centroid = 0.0, weightSum = 0.0
        for t in 0..<frameCount where energy[t] > maxEnergy * 0.01 {
            centroid += Double(centroids[t]) * Double(energy[t]); weightSum += Double(energy[t])
        }
        centroid = weightSum > 0 ? centroid / weightSum : 0

        let windowSeconds = Double(samples.count) / sampleRate
        let wholeFile = fileDuration <= windowSeconds + 0.05
        var tempo: TempoEstimator.Result?
        if windowSeconds >= 1.5 {
            tempo = TempoEstimator.estimate(flux: flux, frameRate: sampleRate / Double(hop),
                                            wholeFileSeconds: wholeFile ? windowSeconds : nil)
        }
        let isLoop = (tempo.map { $0.confidence >= 0.3 && $0.onsetCount >= 4 }) ?? false

        var descriptors = SoundDescriptors(loudnessDB: loudness, peakDB: peakDB, crestDB: peakDB - loudness,
                                           centroidHz: centroid, isLoop: isLoop)
        if isLoop, let tempo {
            descriptors.bpm = tempo.bpm
            descriptors.bpmConfidence = tempo.confidence
            descriptors.keyName = PitchKeyEstimator.key(chroma: chroma)
        } else {
            let loudest = energy.firstIndex(of: maxEnergy) ?? 0
            let center = loudest * hop + Int(0.03 * sampleRate)
            if let hz = PitchKeyEstimator.pitch(signal: samples, sampleRate: sampleRate, center: center) {
                descriptors.pitchHz = hz
                descriptors.keyName = NoteNames.name(forHz: hz)
            }
        }
        return descriptors
    }

    /// RMS (dBFS) of the audible part: frames within 40 dB of the peak, so silent tails do not lower it.
    static func activeLoudness(_ x: [Float], peak: Float) -> Double {
        let frame = 1024
        let floor = peak * peak * 1e-4
        var sum = 0.0, count = 0
        var i = 0
        while i < x.count {
            let end = min(x.count, i + frame)
            var p: Float = 0
            for j in i..<end { p += x[j] * x[j] }
            p /= Float(end - i)
            if p >= floor { sum += Double(p); count += 1 }
            i = end
        }
        return count > 0 ? 10 * log10(sum / Double(count)) : -120
    }
}
