import AVFoundation
import Foundation

public enum AudioDecodeError: Error, CustomStringConvertible {
    case empty
    case conversion(String)
    public var description: String {
        switch self {
        case .empty: return "Audio file has no samples"
        case .conversion(let m): return "Audio conversion failed: \(m)"
        }
    }
}

public struct AnalysisAudio: Sendable {
    /// Mono samples at the requested analysis rate, at most `maxSeconds` long.
    public let samples: [Float]
    /// Duration of the whole file in seconds.
    public let duration: Double
    public let sampleRate: Double
    public let channels: Int
}

public struct LoudnessEnvelope: Sendable {
    /// RMS level of each `hop`-second window, dBFS.
    public let levelsDB: [Float]
    public let hop: Double
    /// Duration of the whole file in seconds.
    public let duration: Double
}

public enum AudioDecoder {
    /// Decodes the first `maxSeconds` of a file to mono float at `sampleRate` for analysis.
    public static func decodeForAnalysis(url: URL, maxSeconds: Double = 4,
                                         sampleRate analysisRate: Double = 32_000) throws -> AnalysisAudio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let total = file.length
        guard total > 0 else { throw AudioDecodeError.empty }

        let frames = AVAudioFrameCount(min(total, Int64(maxSeconds * format.sampleRate)))
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw AudioDecodeError.conversion("buffer allocation")
        }
        try file.read(into: input, frameCount: frames)

        let duration = Double(total) / format.sampleRate
        let mono = try toMono(input, rate: analysisRate)
        return AnalysisAudio(samples: mono, duration: duration,
                             sampleRate: format.sampleRate, channels: Int(format.channelCount))
    }

    /// Length and format of a file without decoding it.
    public static func fileInfo(url: URL) throws -> (duration: Double, sampleRate: Double, channels: Int) {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard file.length > 0, rate > 0 else { throw AudioDecodeError.empty }
        return (Double(file.length) / rate, rate, Int(file.processingFormat.channelCount))
    }

    /// Loudness of a (possibly very long) file as RMS dBFS per `hop` seconds of the mono mix.
    /// Reads in chunks, so memory stays flat however long the file is.
    public static func loudnessEnvelope(url: URL, hop: Double = 0.05) throws -> LoudnessEnvelope {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let total = Int(file.length)
        guard total > 0 else { throw AudioDecodeError.empty }
        let channels = Int(format.channelCount)
        let window = max(1, Int((hop * format.sampleRate).rounded()))
        let chunkFrames = AVAudioFrameCount(max(window, Int(format.sampleRate * 10) / window * window))
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw AudioDecodeError.conversion("buffer allocation")
        }
        var levels: [Float] = []
        levels.reserveCapacity(total / window + 1)
        var energy = 0.0
        var inWindow = 0
        func closeWindow() {
            let rms = (energy / Double(max(1, inWindow))).squareRoot()
            levels.append(Float(20 * log10(max(rms, 1e-9))))
            energy = 0; inWindow = 0
        }
        var position = 0
        while position < total {
            chunk.frameLength = 0
            try file.read(into: chunk, frameCount: min(chunkFrames, AVAudioFrameCount(total - position)))
            let count = Int(chunk.frameLength)
            guard count > 0, let data = chunk.floatChannelData else { break }
            for i in 0..<count {
                var mix: Float = 0
                for c in 0..<channels { mix += data[c][i] }
                mix /= Float(channels)
                energy += Double(mix) * Double(mix)
                inWindow += 1
                if inWindow == window { closeWindow() }
            }
            position += count
        }
        if inWindow > window / 2 { closeWindow() }
        return LoudnessEnvelope(levelsDB: levels, hop: Double(window) / format.sampleRate,
                                duration: Double(total) / format.sampleRate)
    }

    /// Decodes `seconds` of a file starting at `start`, as mono float at `sampleRate`. Clipped at the end of the file.
    public static func decode(url: URL, start: Double, seconds: Double, sampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let first = min(file.length, max(0, Int64((start * format.sampleRate).rounded())))
        let frames = AVAudioFrameCount(max(0, min(file.length - first, Int64((seconds * format.sampleRate).rounded()))))
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return [] }
        file.framePosition = first
        try file.read(into: input, frameCount: frames)
        return try toMono(input, rate: sampleRate)
    }

    static func toMono(_ input: AVAudioPCMBuffer, rate analysisRate: Double) throws -> [Float] {
        let src = input.format
        guard let dst = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: analysisRate,
                                      channels: 1, interleaved: false) else {
            throw AudioDecodeError.conversion("target format")
        }
        if src.sampleRate == analysisRate && src.channelCount == 1, let ch = input.floatChannelData {
            return Array(UnsafeBufferPointer(start: ch[0], count: Int(input.frameLength)))
        }
        guard let converter = AVAudioConverter(from: src, to: dst) else {
            throw AudioDecodeError.conversion("unsupported format")
        }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * analysisRate / src.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: capacity) else {
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
        guard let ch = output.floatChannelData else { throw AudioDecodeError.conversion("no channel data") }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(output.frameLength)))
    }
}
