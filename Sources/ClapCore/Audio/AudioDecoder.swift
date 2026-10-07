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
