import Foundation

/// How to bend a sample so it fits a project: playback rate for loops and a pitch shift for tonal sounds.
public enum TempoSync {
    /// The playback rate that brings a loop at `sampleBPM` to `projectBPM`. A loop detected at half or double
    /// the project's feel is played at the nearer of the three options, so a 70 BPM loop is not squeezed to
    /// fit 140 when it already sits there at double time.
    public static func rate(sampleBPM: Double?, projectBPM: Double?) -> Float {
        guard let sampleBPM, let projectBPM, sampleBPM > 20, projectBPM > 20 else { return 1 }
        let direct = projectBPM / sampleBPM
        let best = [direct, direct / 2, direct * 2].min { abs(log2($0)) < abs(log2($1)) } ?? direct
        return Float(min(2, max(0.5, best)))
    }

    /// Semitones (-6...+6, the shortest way round) that move a sample's key or note to the project's key.
    /// Only the tonic matters: "A1" and "A minor" both count as A.
    public static func semitones(sampleKey: String?, projectTonic: String?) -> Int {
        guard let sampleKey, let projectTonic,
              let from = DescriptorFilter.tonic(of: sampleKey).flatMap({ NoteNames.sharps.firstIndex(of: $0) }),
              let to = NoteNames.sharps.firstIndex(of: projectTonic) else { return 0 }
        var shift = (to - from) % 12
        if shift > 6 { shift -= 12 }
        if shift < -6 { shift += 12 }
        return shift
    }
}
