import AVFoundation
import Foundation

/// Format conversion shared by playback decoding and trimming.
public enum AudioConvert {
    /// `highQuality` uses the slowest, cleanest sample-rate converter (for files that are written out).
    public static func convert(_ input: AVAudioPCMBuffer, to format: AVAudioFormat, highQuality: Bool = false) throws -> AVAudioPCMBuffer {
        let src = input.format
        if src.sampleRate == format.sampleRate && src.channelCount == format.channelCount
            && src.commonFormat == format.commonFormat && src.isInterleaved == format.isInterleaved { return input }
        guard let converter = AVAudioConverter(from: src, to: format) else {
            throw AudioDecodeError.conversion("unsupported format")
        }
        if highQuality { converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * format.sampleRate / src.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioDecodeError.conversion("buffer allocation")
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied { outStatus.pointee = .endOfStream; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error { throw AudioDecodeError.conversion(error?.localizedDescription ?? "unknown") }
        return output
    }
}

/// Reads a part of an audio file straight from disk, so very long files are not decoded whole.
public enum TrimRender {
    /// Reads `start`..<`end` (seconds; to the end of the file when nil), with linear fades at the edges,
    /// optionally converted to `format`. `maxSeconds` limits how much is read. An `edit` is applied before the fades,
    /// so a reversed sound still fades in at its new start.
    public static func read(url: URL, start: Double = 0, end: Double? = nil, fadeIn: Double = 0, fadeOut: Double = 0,
                            edit: SampleEdit? = nil, convertTo format: AVAudioFormat? = nil, maxSeconds: Double? = nil) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let native = file.processingFormat
        let rate = native.sampleRate
        let total = file.length
        let first = min(max(0, Int64(start * rate)), total)
        var last = end.map { min(max(first, Int64($0 * rate)), total) } ?? total
        if let maxSeconds { last = min(last, first + Int64(maxSeconds * rate)) }
        let frames = last - first
        guard frames > 0, var buffer = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: AVAudioFrameCount(frames)) else {
            throw AudioDecodeError.empty
        }
        file.framePosition = first
        try file.read(into: buffer, frameCount: AVAudioFrameCount(frames))
        if let edit, !edit.isNeutral { buffer = EditRender.apply(buffer, edit: edit) }
        applyFades(to: buffer, fadeIn: fadeIn, fadeOut: fadeOut)
        guard let format else { return buffer }
        return try AudioConvert.convert(buffer, to: format)
    }

    /// Linear fade in and out, in place. The two never overlap: a short buffer gets shorter fades.
    public static func applyFades(to buffer: AVAudioPCMBuffer, fadeIn: Double, fadeOut: Double) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength), rate = buffer.format.sampleRate
        let inFrames = min(Int(max(0, fadeIn) * rate), n / 2)
        let outFrames = min(Int(max(0, fadeOut) * rate), n - inFrames)
        for c in 0..<Int(buffer.format.channelCount) {
            for i in 0..<inFrames { data[c][i] *= Float(i) / Float(inFrames) }
            for j in 0..<outFrames { data[c][n - 1 - j] *= Float(j) / Float(outFrames) }
        }
    }
}

/// Min/max envelope of a whole file for drawing, read in chunks so length does not matter.
public enum WaveformPeaks {
    public static func compute(url: URL, bins: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let total = Int(file.length)
        guard total > 0, bins > 0, let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 16) else { return [] }
        var out = [Float](repeating: 0, count: bins * 2)
        let channels = Int(file.processingFormat.channelCount)
        var position = 0
        while position < total {
            try file.read(into: chunk, frameCount: min(chunk.frameCapacity, AVAudioFrameCount(total - position)))
            let count = Int(chunk.frameLength)
            guard count > 0, let data = chunk.floatChannelData else { break }
            for i in 0..<count {
                let bin = min(bins - 1, (position + i) * bins / total)
                for c in 0..<channels {
                    let v = data[c][i]
                    if v < out[bin * 2] { out[bin * 2] = v }
                    if v > out[bin * 2 + 1] { out[bin * 2 + 1] = v }
                }
            }
            position += count
        }
        return out
    }
}
