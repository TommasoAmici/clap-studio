import AVFoundation
import Foundation

/// Gain that brings a preview to a common level so samples can be compared by ear.
public enum LoudnessMatch {
    public static let targetDB = -18.0
    /// Never boost more than this, so a near-silent file is not turned into hiss.
    public static let maxBoostDB = 18.0
    public static let maxCutDB = 24.0
    /// Peaks stay below this level after the gain is applied.
    public static let ceilingDB = -1.0

    /// - Parameters:
    ///   - loudnessDB: the sample's measured level (RMS over the active part).
    ///   - peakDB: its peak level, used to avoid clipping when boosting.
    public static func gainDB(loudnessDB: Double?, peakDB: Double?) -> Float {
        guard let loudnessDB, loudnessDB > -90 else { return 0 }
        var gain = min(maxBoostDB, max(-maxCutDB, targetDB - loudnessDB))
        if let peakDB, peakDB > -90 { gain = min(gain, ceilingDB - peakDB) }
        return Float(gain)
    }

    /// Changes the level of rendered audio in place to what `gainDB` gives for it (the same rule the preview uses,
    /// so a sample sounds as loud on the module as it does in the app with level matching on). Measured on the
    /// audio as it is, after any trim, so a quiet part cut from a loud file is matched as what it now is.
    /// Returns the gain applied, in dB.
    @discardableResult
    static func apply(to buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        var mix = [Float](repeating: 0, count: n)
        var peak: Float = 0
        for c in 0..<channels {
            for i in 0..<n {
                mix[i] += data[c][i] / Float(channels)
                peak = max(peak, abs(data[c][i]))
            }
        }
        guard peak > 1e-6 else { return 0 }
        let mixPeak = mix.reduce(Float(0)) { max($0, abs($1)) }
        let loudness = DescriptorAnalyzer.activeLoudness(mix, peak: max(mixPeak, 1e-6))
        let gain = gainDB(loudnessDB: loudness, peakDB: 20 * Double(log10(peak)))
        guard abs(gain) > 0.01 else { return 0 }
        let factor = Float(pow(10, Double(gain) / 20))
        for c in 0..<channels { for i in 0..<n { data[c][i] *= factor } }
        return gain
    }
}
