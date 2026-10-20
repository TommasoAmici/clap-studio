import Accelerate
import AVFoundation
import Foundation

/// How one melody note sounds: the sample tuned like a tape (pitch and length move together, as with the speed in
/// Edit sound), then cut to the length of the note.
public enum MelodyVoice {
    /// How far a sample can be tuned from its own note, each way.
    public static let tuneRange = 24
    /// A note that is cut short fades out over this long, so it does not click.
    static let releaseSeconds = 0.012

    /// Semitones to tune the sample for a note, so the root note plays it as it is.
    public static func semitones(note: Int, root: Int) -> Int { min(max(note - root, -tuneRange), tuneRange) }

    /// The whole sample tuned by `semitones`; the same buffer when there is nothing to change.
    public static func pitched(_ buffer: AVAudioPCMBuffer, semitones: Int) -> AVAudioPCMBuffer {
        semitones == 0 ? buffer : EditRender.apply(buffer, edit: SampleEdit(speedSemitones: Double(semitones)))
    }

    /// A copy of the sound for one note: cut at `duration` seconds (a sound shorter than that plays to its end),
    /// scaled by `velocity`, with a tiny fade at the edges. nil when there is nothing to play.
    public static func shaped(_ buffer: AVAudioPCMBuffer, duration: Double, velocity: Float) -> AVAudioPCMBuffer? {
        let rate = buffer.format.sampleRate
        let available = Int(buffer.frameLength)
        let wanted = max(1, Int((duration * rate).rounded()))
        let frames = min(available, wanted)
        guard frames > 0, let source = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(frames)),
              let target = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(frames)
        var gain = min(max(velocity.isFinite ? velocity : 1, 0), 1)
        for c in 0..<Int(buffer.format.channelCount) {
            vDSP_vsmul(source[c], 1, &gain, target[c], 1, vDSP_Length(frames))
        }
        TrimRender.applyFades(to: out, fadeIn: SampleTrim.declick, fadeOut: wanted < available ? releaseSeconds : 0)
        return out
    }
}
