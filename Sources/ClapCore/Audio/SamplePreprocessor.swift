import Foundation

/// Standardises a mono signal before it is embedded, so a sound's level and the silence around it do not decide
/// where it lands on the map. Only the embedding sees this: loudness, duration and previews use the original audio.
public enum SamplePreprocessor {
    /// Active part of the sound brought to this RMS level (dBFS).
    public static let targetRMSDB = -18.0
    /// Peaks stay at or below this level (dBFS) after the gain.
    public static let peakCeilingDB = -1.0
    /// Quiet files are boosted at most this much, so their noise floor is not turned into the sound.
    public static let maxBoostDB = 30.0
    /// Silence is any stretch whose RMS stays this far (dB) below the file's peak.
    public static let silenceThresholdDB = -60.0
    /// Silence kept before the first sound, so attacks are not cut.
    public static let preRollSeconds = 0.005
    /// Length of the RMS window used to find where sound starts and stops.
    public static let windowSeconds = 0.005

    /// Trims leading and trailing silence, keeps a short pre-roll and applies one gain for the whole sound.
    /// With `trimSilence` off (loops, whose silence is part of the bar) only the gain is applied.
    /// Silent input, and input containing NaN or infinite samples, is returned unchanged.
    public static func prepare(_ signal: [Float], sampleRate: Double, trimSilence: Bool = true) -> [Float] {
        let peak = signal.reduce(Float(0)) { max($0, abs($1)) }
        // A NaN sample never wins `max`, so check every sample: one bad sample must not turn the gain into NaN.
        guard peak.isFinite, peak > 1e-6, signal.allSatisfy(\.isFinite) else { return signal }

        var out: [Float]
        if trimSilence {
            let active = activeRange(signal, peak: peak, sampleRate: sampleRate)
            // Every output starts with exactly the same pre-roll of silence, so the onset sits at a fixed time
            // whether the file had silence before it or not.
            let preRoll = Int((preRollSeconds * sampleRate).rounded())
            out = [Float](repeating: 0, count: preRoll) + signal[active]
        } else {
            out = signal
        }

        let power = out.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(out.count)
        let outPeak = Double(out.reduce(Float(0)) { max($0, abs($1)) })
        let gainDB = min(maxBoostDB,
                         targetRMSDB - 10 * log10(max(power, 1e-20)),
                         peakCeilingDB - 20 * log10(max(outPeak, 1e-20)))
        let gain = Float(pow(10, gainDB / 20))
        for i in out.indices { out[i] *= gain }
        return out
    }

    /// From the first to the last window that is louder than the silence threshold.
    /// A window ending at `e` covers the `windowLength` samples before it. The start is sample-accurate; the end
    /// can run up to one window (5 ms) past the last loud sample, because that window still contains it.
    /// Never empty for a signal whose peak is above the threshold: the window holding the peak is always loud,
    /// so a failed search falls back to the whole signal.
    ///
    /// Window energy comes from prefix sums in `Double`. Digital silence adds exactly 0, so silent stretches
    /// difference to exactly 0; rounding only matters for material within a few dB of `silenceThresholdDB`.
    static func activeRange(_ x: [Float], peak: Float, sampleRate: Double) -> Range<Int> {
        let n = x.count
        guard n > 0 else { return 0..<0 }
        let windowLength = max(1, Int(windowSeconds * sampleRate))
        var squares = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { squares[i + 1] = squares[i] + Double(x[i]) * Double(x[i]) }

        let threshold = Double(peak) * pow(10, silenceThresholdDB / 20)
        func isLoud(endingAt end: Int) -> Bool {
            let start = max(0, end - windowLength)
            let meanSquare = (squares[end] - squares[start]) / Double(end - start)
            return meanSquare.squareRoot() >= threshold
        }

        guard let first = (1...n).first(where: isLoud(endingAt:)),
              let last = stride(from: n, through: 1, by: -1).first(where: isLoud(endingAt:)) else {
            return 0..<n
        }
        // The window ending at `first` is the first one with sound in it, so the sound starts at `first - 1`.
        return (first - 1)..<last
    }
}
