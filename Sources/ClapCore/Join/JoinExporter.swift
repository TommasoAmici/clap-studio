import AVFoundation
import Foundation

public struct JoinSource: Sendable {
    public var url: URL
    public var trim: SampleTrim?
    public var name: String

    public init(url: URL, trim: SampleTrim? = nil, name: String? = nil) {
        self.url = url
        self.trim = trim
        self.name = name ?? url.deletingPathExtension().lastPathComponent
    }
}

/// Writes new joined WAV files; sources and existing destination files are only read.
public enum JoinExporter {
    public static func export(_ sources: [JoinSource], settings: JoinSettings, to folder: URL) throws -> [URL] {
        try Task.checkCancellation()
        guard settings.isValid, !sources.isEmpty else { throw JoinError.invalidSettings }
        let fm = FileManager.default
        for source in sources { try preflight(source, settings: settings) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appendingPathComponent(".clap-join-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: JoinPlanner.sampleRate,
                                  channels: settings.mono ? 1 : 2, interleaved: false)!
        var converted: [URL] = []
        var frames: [Int64] = []
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent("source-\(index).wav")
            try render(source, format: format, to: destination)
            let count = try AVAudioFile(forReading: destination).length
            guard Double(count) <= settings.maxSeconds * JoinPlanner.sampleRate else { throw JoinError.tooLong(source.name) }
            converted.append(destination)
            frames.append(count)
        }
        let plans = try JoinPlanner.plan(frameCounts: frames, settings: settings)
        let names = sources.map(\.name)
        var outputs: [URL] = []
        for (index, plan) in plans.enumerated() {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent("Joined \(index + 1).wav")
            try write(plan, sources: converted, format: format, to: destination)
            try JoinedCueWriter.write(regions: plan.regions, names: names, to: destination)
            let check = try AVAudioFile(forReading: destination)
            guard check.length == plan.frameCount, check.processingFormat.sampleRate == JoinPlanner.sampleRate,
                  check.processingFormat.channelCount == format.channelCount,
                  check.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 16 else {
                throw JoinError.verificationFailed
            }
            outputs.append(destination)
        }

        var published: [URL] = []
        do {
            for output in outputs {
                try Task.checkCancellation()
                let target = SampleExporter.uniqueURL(in: folder, fileName: output.lastPathComponent)
                try fm.moveItem(at: output, to: target)
                published.append(target)
            }
        } catch {
            for output in published { try? fm.removeItem(at: output) }
            throw error
        }
        return published
    }

    private static func preflight(_ source: JoinSource, settings: JoinSettings) throws {
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: source.url)
        guard file.processingFormat.channelCount <= 2 else { throw JoinError.unsupportedChannels(source.name) }
        let rate = file.processingFormat.sampleRate
        let duration = Double(file.length) / rate
        let trim = source.trim
        let start = trim?.start ?? 0, end = trim?.end ?? duration
        guard start.isFinite, end.isFinite, trim?.fadeOut.isFinite != false,
              trim?.edit.gainDB.isFinite != false, trim?.edit.speedSemitones.isFinite != false,
              trim?.edit.lowPassHz?.isFinite != false, trim?.edit.highPassHz?.isFinite != false else {
            throw JoinError.invalidSettings
        }
        guard rate.isFinite, rate > 0, start >= 0, end > start, end <= duration else {
            throw JoinError.invalidSettings
        }
        let readFrames = max(0, min(end, duration) - min(max(0, start), duration)) * rate
        let speed = pow(2, (trim?.edit.clamped().speedSemitones ?? 0) / 12)
        guard readFrames / rate / speed <= settings.maxSeconds + 1 / JoinPlanner.sampleRate else {
            throw JoinError.tooLong(source.name)
        }
        // Rendering sound edits needs a complete buffer. Bound it before converting to AVAudioFrameCount.
        guard readFrames <= 64_000_000 else { throw JoinError.tooLarge(source.name) }
    }

    private static func render(_ source: JoinSource, format: AVAudioFormat, to destination: URL) throws {
        let trim = source.trim
        let input = try TrimRender.read(url: source.url, start: trim?.start ?? 0, end: trim?.end,
                                       fadeIn: trim == nil ? 0 : SampleTrim.declick,
                                       fadeOut: trim?.effectiveFadeOut ?? 0, edit: trim?.edit)
        let buffer = try AudioConvert.convert(input, to: format, highQuality: true)
        try Task.checkCancellation()
        let file = try AVAudioFile(forWriting: destination, settings: settings(for: format),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private static func settings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
    }

    private static func write(_ plan: JoinedFilePlan, sources: [URL], format: AVAudioFormat, to destination: URL) throws {
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536),
              let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else {
            throw AudioDecodeError.empty
        }
        for channel in 0..<Int(format.channelCount) {
            silence.floatChannelData![channel].initialize(repeating: 0, count: Int(silence.frameCapacity))
        }
        let output = try AVAudioFile(forWriting: destination, settings: settings(for: format),
                                    commonFormat: .pcmFormatFloat32, interleaved: false)
        var position: Int64 = 0
        for region in plan.regions {
            while position < region.startFrame {
                try Task.checkCancellation()
                silence.frameLength = AVAudioFrameCount(min(Int64(silence.frameCapacity), region.startFrame - position))
                try output.write(from: silence)
                position += Int64(silence.frameLength)
            }
            let input = try AVAudioFile(forReading: sources[region.sourceIndex])
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: chunk, frameCount: AVAudioFrameCount(min(Int64(chunk.frameCapacity), input.length - input.framePosition)))
                guard chunk.frameLength > 0 else { throw JoinError.verificationFailed }
                try output.write(from: chunk)
                position += Int64(chunk.frameLength)
            }
        }
    }
}
