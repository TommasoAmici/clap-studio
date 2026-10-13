import AVFoundation
import Foundation

/// Non-destructive changes to the sound of a sample. They are kept with the trim and applied whenever the sample is
/// played in the drum machine, previewed or exported; the file itself is never changed.
public struct SampleEdit: Equatable, Sendable {
    public static let gainRange = -24.0...12.0
    public static let speedRange = -24.0...24.0
    public static let filterRange = 20.0...20_000.0

    public var reverse = false
    /// Volume change in decibels.
    public var gainDB = 0.0
    /// Tape-style speed change in semitones: pitch and length move together (+12 is an octave up, half as long).
    public var speedSemitones = 0.0
    /// Frequencies above this are removed (nil: off).
    public var lowPassHz: Double?
    /// Frequencies below this are removed (nil: off).
    public var highPassHz: Double?

    public init(reverse: Bool = false, gainDB: Double = 0, speedSemitones: Double = 0, lowPassHz: Double? = nil, highPassHz: Double? = nil) {
        self.reverse = reverse; self.gainDB = gainDB; self.speedSemitones = speedSemitones
        self.lowPassHz = lowPassHz; self.highPassHz = highPassHz
    }

    public var isNeutral: Bool { self == SampleEdit() }

    /// True when the edit changes how long the sound is or which way it runs, so a playhead along the original
    /// file would be wrong.
    public var changesTiming: Bool { reverse || speedSemitones != 0 }

    /// How much longer the sound plays than its source part (1 for no change).
    public var lengthFactor: Double { pow(2, -speedSemitones / 12) }

    /// Values brought into range (tiny changes count as none).
    public func clamped() -> SampleEdit {
        func snap(_ v: Double) -> Double { abs(v) < 0.05 ? 0 : v }
        return SampleEdit(reverse: reverse,
                          gainDB: snap(min(max(gainDB, Self.gainRange.lowerBound), Self.gainRange.upperBound)),
                          speedSemitones: snap(min(max(speedSemitones, Self.speedRange.lowerBound), Self.speedRange.upperBound)),
                          lowPassHz: lowPassHz.map { min(max($0, Self.filterRange.lowerBound), Self.filterRange.upperBound) },
                          highPassHz: highPassHz.map { min(max($0, Self.filterRange.lowerBound), Self.filterRange.upperBound) })
    }

    /// Short description for lists: "reversed, +3 dB, low-pass 4 kHz".
    public var summary: String {
        var parts: [String] = []
        if reverse { parts.append("reversed") }
        if speedSemitones != 0 { parts.append(String(format: "%+.1f st", speedSemitones)) }
        if gainDB != 0 { parts.append(String(format: "%+.1f dB", gainDB)) }
        if let hz = highPassHz { parts.append("high-pass " + Self.hertz(hz)) }
        if let hz = lowPassHz { parts.append("low-pass " + Self.hertz(hz)) }
        return parts.joined(separator: ", ")
    }

    public static func hertz(_ hz: Double) -> String {
        hz >= 1000 ? String(format: "%.1f kHz", hz / 1000).replacingOccurrences(of: ".0 kHz", with: " kHz") : String(format: "%.0f Hz", hz)
    }
}

/// Applies a `SampleEdit` to audio: speed, then reversing, the filters, and last the volume. The result is clipped at
/// full scale, so a boost never wraps around in a file.
public enum EditRender {
    public static func apply(_ buffer: AVAudioPCMBuffer, edit: SampleEdit) -> AVAudioPCMBuffer {
        let edit = edit.clamped()
        guard !edit.isNeutral, buffer.frameLength > 0, let input = buffer.floatChannelData else { return buffer }
        let rate = buffer.format.sampleRate
        let channels = Int(buffer.format.channelCount)
        var channelData: [[Float]] = (0..<channels).map { Array(UnsafeBufferPointer(start: input[$0], count: Int(buffer.frameLength))) }

        if edit.speedSemitones != 0 {
            let ratio = pow(2, edit.speedSemitones / 12)
            // Going faster would fold high frequencies back down, so they are taken out first.
            if ratio > 1 { channelData = channelData.map { filter($0, rate: rate, hz: 0.45 * rate / ratio, highPass: false) } }
            channelData = channelData.map { resample($0, ratio: ratio) }
        }
        if edit.reverse { channelData = channelData.map { Array($0.reversed()) } }
        if let hz = edit.highPassHz { channelData = channelData.map { filter($0, rate: rate, hz: hz, highPass: true) } }
        if let hz = edit.lowPassHz, hz < rate / 2 { channelData = channelData.map { filter($0, rate: rate, hz: hz, highPass: false) } }
        let gain = Float(pow(10, edit.gainDB / 20))

        let frames = channelData.first?.count ?? 0
        guard frames > 0, let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(frames)),
              let output = out.floatChannelData else { return buffer }
        out.frameLength = AVAudioFrameCount(frames)
        for c in 0..<channels {
            channelData[c].withUnsafeBufferPointer { source in
                for i in 0..<frames { output[c][i] = max(-1, min(1, source[i] * gain)) }
            }
        }
        return out
    }

    /// Plays the samples `ratio` times as fast, reading between them with cubic interpolation.
    static func resample(_ x: [Float], ratio: Double) -> [Float] {
        let count = max(1, Int(Double(x.count) / ratio))
        var out = [Float](repeating: 0, count: count)
        func at(_ i: Int) -> Float { x[min(max(i, 0), x.count - 1)] }
        for n in 0..<count {
            let position = Double(n) * ratio
            let i = Int(position)
            let t = Float(position - Double(i))
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            out[n] = p1 + 0.5 * t * (p2 - p0 + t * (2 * p0 - 5 * p1 + 4 * p2 - p3 + t * (3 * (p1 - p2) + p3 - p0)))
        }
        return out
    }

    /// Two cascaded 2-pole Butterworth sections: 24 dB per octave.
    static func filter(_ x: [Float], rate: Double, hz: Double, highPass: Bool) -> [Float] {
        let cutoff = min(max(hz, 5), rate * 0.49)
        let w0 = 2 * Double.pi * cutoff / rate
        let alpha = sin(w0) / (2 * 0.70710678)
        let cosw = cos(w0)
        let a0 = 1 + alpha
        let b0 = (highPass ? (1 + cosw) / 2 : (1 - cosw) / 2) / a0
        let b1 = (highPass ? -(1 + cosw) : (1 - cosw)) / a0
        let b2 = b0
        let a1 = -2 * cosw / a0, a2 = (1 - alpha) / a0
        var y = x
        for _ in 0..<2 {
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in 0..<y.count {
                let input = Double(y[i])
                let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = input; y2 = y1; y1 = output
                y[i] = Float(output)
            }
        }
        return y
    }
}
