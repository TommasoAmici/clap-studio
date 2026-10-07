import Foundation

/// Measured properties of a sound, shown as columns and used for filtering and tempo sync.
public struct SoundDescriptors: Sendable, Equatable {
    /// Bump when the algorithms change so existing libraries are re-analysed.
    public static let version = 1

    /// Average level of the audible part, dBFS.
    public var loudnessDB: Double
    public var peakDB: Double
    /// Peak minus average level, dB. Punchy transients score high, sustained sounds low.
    public var crestDB: Double
    /// Spectral centroid ("perceived brightness"), Hz.
    public var centroidHz: Double
    public var isLoop: Bool
    public var bpm: Double?
    /// 0...1, how regular the rhythm is.
    public var bpmConfidence: Double
    public var pitchHz: Double?
    /// Note name for tonal one-shots ("A1"), musical key for loops ("F minor").
    public var keyName: String?

    public init(loudnessDB: Double, peakDB: Double, crestDB: Double, centroidHz: Double, isLoop: Bool,
                bpm: Double? = nil, bpmConfidence: Double = 0, pitchHz: Double? = nil, keyName: String? = nil) {
        self.loudnessDB = loudnessDB; self.peakDB = peakDB; self.crestDB = crestDB; self.centroidHz = centroidHz
        self.isLoop = isLoop; self.bpm = bpm; self.bpmConfidence = bpmConfidence
        self.pitchHz = pitchHz; self.keyName = keyName
    }
}

public enum NoteNames {
    static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// "A4" for 440 Hz.
    public static func name(forHz hz: Double) -> String? {
        guard hz > 20, hz < 8_000 else { return nil }
        let midi = Int((69 + 12 * log2(hz / 440)).rounded())
        guard midi >= 0 else { return nil }
        return "\(sharps[midi % 12])\(midi / 12 - 1)"
    }
}
