import AVFoundation
import Foundation

/// Converts each source once; long unedited sounds are read as a stream.
enum JoinSourceRenderer {
    static func write(_ source: JoinSource, format: AVAudioFormat, to destination: URL) throws {
        if let trim = source.trim, !trim.edit.isNeutral {
            let input = try TrimRender.read(url: source.url, start: trim.start, end: trim.end,
                                           fadeIn: SampleTrim.declick, fadeOut: trim.effectiveFadeOut, edit: trim.edit)
            let buffer = try AudioConvert.convert(input, to: format, highQuality: true)
            try Task.checkCancellation()
            let file = try AVAudioFile(forWriting: destination, settings: JoinExporter.settings(for: format),
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            return
        }
        let input = try AVAudioFile(forReading: source.url)
        let rate = input.processingFormat.sampleRate
        let first = Int64((source.trim?.start ?? 0) * rate)
        let last = source.trim.map { min(input.length, Int64($0.end * rate)) } ?? input.length
        let length = last - first
        guard length > 0, let chunk = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 65_536),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else { throw AudioDecodeError.empty }
        input.framePosition = first
        let file = try AVAudioFile(forWriting: destination, settings: JoinExporter.settings(for: format),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        func read(_ requested: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
            try Task.checkCancellation()
            guard input.framePosition < last else { return nil }
            let position = input.framePosition - first
            try input.read(into: chunk, frameCount: min(requested, chunk.frameCapacity, AVAudioFrameCount(min(last - input.framePosition, 65_536))))
            guard chunk.frameLength > 0 else { throw JoinError.verificationFailed }
            if let trim = source.trim { fade(chunk, position: position, length: length, trim: trim) }
            return chunk
        }
        if input.processingFormat == format {
            while let chunk = try read(65_536) { try file.write(from: chunk) }
            return
        }
        guard let converter = AVAudioConverter(from: input.processingFormat, to: format) else {
            throw AudioDecodeError.conversion("unsupported output format")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        while true {
            try Task.checkCancellation()
            let position = input.framePosition
            var conversionError: NSError?
            var readError: Error?
            let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
                do {
                    guard let chunk = try read(requested) else { inputStatus.pointee = .endOfStream; return nil }
                    inputStatus.pointee = .haveData
                    return chunk
                } catch { readError = error; inputStatus.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }
            if status == .error { throw AudioDecodeError.conversion(conversionError?.localizedDescription ?? "unknown") }
            if output.frameLength > 0 { try file.write(from: output) }
            if status == .endOfStream { break }
            guard output.frameLength > 0 || input.framePosition > position else { throw JoinError.verificationFailed }
        }
    }

    private static func fade(_ buffer: AVAudioPCMBuffer, position: Int64, length: Int64, trim: SampleTrim) {
        let rate = buffer.format.sampleRate
        let fadeIn = min(Int64(SampleTrim.declick * rate), length / 2)
        let fadeOut = min(Int64(trim.effectiveFadeOut * rate), length - fadeIn)
        for channel in 0..<Int(buffer.format.channelCount) {
            let data = buffer.floatChannelData![channel]
            for index in 0..<Int(buffer.frameLength) {
                let frame = position + Int64(index)
                if frame < fadeIn { data[index] *= Float(frame) / Float(fadeIn) }
                if frame >= length - fadeOut { data[index] *= Float(length - 1 - frame) / Float(fadeOut) }
            }
        }
    }
}
