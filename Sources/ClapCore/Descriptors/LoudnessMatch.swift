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
}
