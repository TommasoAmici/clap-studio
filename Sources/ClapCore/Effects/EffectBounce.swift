import AVFoundation
import CVST3
import Foundation

/// Renders independent stereo WAV copies through a reusable VST3 recipe.
public enum EffectBounce {
    /// Additional audio allowed after each effect, including infinite reverb tails.
    public static let maximumTailSeconds = 10.0

    @MainActor public static func write(source: URL, trim: SampleTrim?, chain: [EffectSlot], to destination: URL, tailSeconds: Double = 2, protectedSources: [URL] = []) async throws {
        guard chain.contains(where: { !$0.bypass }) else {
            try await writeInProcess(source: source, trim: trim, chain: [], to: destination, protectedSources: protectedSources)
            return
        }
        try await offMain { try protect(source: source, destination: destination, originals: protectedSources) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clap-vst-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.wav"), output = folder.appendingPathComponent("output.wav")
        try await writeInProcess(source: source, trim: trim, chain: [], to: input)
        let recipe = chain.map { slot in
            var slot = slot
            for index in slot.parameters.indices {
                let value = slot.parameters[index].value
                slot.parameters[index].value = value.isFinite ? min(1, max(0, value)) : 0
            }
            return slot
        }
        _ = try await VST3HostRequest.send(VST3HostRequest(operation: .render, chain: recipe, source: input,
                                                         destination: output, tailSeconds: tailSeconds.isFinite ? tailSeconds : 2), timeout: 300)
        try Task.checkCancellation()
        // The app verifies and saves the helper's result through the same atomic writer.
        try await writeInProcess(source: output, trim: nil, chain: [], to: destination, protectedSources: [source] + protectedSources)
    }

    @MainActor static func writeInProcess(source: URL, trim: SampleTrim?, chain: [EffectSlot], to destination: URL, tailSeconds: Double = 2, protectedSources: [URL] = [], heartbeat: URL? = nil) async throws {
        var audio = try await offMain {
            try Task.checkCancellation()
            try protect(source: source, destination: destination, originals: protectedSources)
            let input = try TrimRender.read(url: source, start: trim?.start ?? 0, end: trim?.end,
                                            fadeIn: trim == nil ? 0 : SampleTrim.declick,
                                            fadeOut: trim?.effectiveFadeOut ?? 0, edit: trim?.edit)
            guard input.format.channelCount <= 2 else { throw VST3Error.message("Effects currently support mono and stereo samples.") }
            guard let stereo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: input.format.sampleRate, channels: 2, interleaved: false) else { throw AudioDecodeError.empty }
            let buffer = input.format.channelCount == 2 ? input : try AudioConvert.convert(input, to: stereo, highQuality: true)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { throw AudioDecodeError.empty }
            return StereoAudio(left: Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))),
                               right: Array(UnsafeBufferPointer(start: channels[1], count: Int(buffer.frameLength))), rate: buffer.format.sampleRate)
        }
        for slot in chain where !slot.bypass {
            try Task.checkCancellation()
            let instance = try VST3Instance(slot: slot)
            defer { instance.close() }
            try instance.prepare(rate: audio.rate)
            let latency = Int(clap_vst3_latency(instance.effect))
            guard latency <= Int(audio.rate * 30) else { throw VST3Error.message("This effect reports more than 30 seconds of latency.") }
            let reportedTail = clap_vst3_tail(instance.effect)
            let extraTail = tailSeconds.isFinite ? min(maximumTailSeconds, max(0, tailSeconds)) : 2
            let tail = min(max(Int(reportedTail), Int(audio.rate * extraTail)), Int(audio.rate * maximumTailSeconds))
            let input = audio
            audio = try await offMain {
                try process(input, instance: instance, parameters: slot.parameters, latency: latency, tail: tail, heartbeat: heartbeat)
            }
        }
        try Task.checkCancellation()
        let result = audio
        try await offMain {
            try save(result, to: destination, fileManager: .default)
        }
    }

    private static func protect(source: URL, destination: URL, originals: [URL]) throws {
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        let targetID = (try? destination.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier) as? NSObject
        guard targetID != nil || FileManager.default.fileExists(atPath: target.path) else { return }
        for original in [source] + originals {
            try Task.checkCancellation()
            let sourceID = (try? original.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier) as? NSObject
            guard original.resolvingSymlinksInPath().standardizedFileURL != target,
                  sourceID == nil || targetID == nil || sourceID != targetID else {
                throw VST3Error.message("Choose a new file name. Original samples are only read, never changed.")
            }
        }
    }

    private static func offMain<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    private struct StereoAudio: Sendable { var left: [Float]; var right: [Float]; let rate: Double }

    private static func process(_ input: StereoAudio, instance: VST3Instance, parameters: [VST3Parameter], latency: Int, tail: Int, heartbeat: URL?) throws -> StereoAudio {
        let total = input.left.count + latency + tail
        var left = [Float](repeating: 0, count: total), right = left
        let ids = parameters.map(\.id), values = parameters.map { min(1, max(0, $0.value.isFinite ? $0.value : 0)) }
        var lastHeartbeat = Date.distantPast
        for start in stride(from: 0, to: total, by: 512) {
            try Task.checkCancellation()
            let frames = min(512, total - start)
            var blockL = [Float](repeating: 0, count: frames), blockR = blockL
            if start < input.left.count {
                let count = min(frames, input.left.count - start)
                blockL.replaceSubrange(0..<count, with: input.left[start..<start + count])
                blockR.replaceSubrange(0..<count, with: input.right[start..<start + count])
            }
            guard clap_vst3_process(instance.effect, &blockL, &blockR, Int32(frames), ids, values, start == 0 ? Int32(ids.count) : 0) != 0 else {
                throw VST3Error.message("The effect could not process this sample. The original file is unchanged.")
            }
            guard blockL.allSatisfy(\.isFinite), blockR.allSatisfy(\.isFinite) else { throw VST3Error.message("The effect produced invalid audio. Nothing was saved.") }
            left.replaceSubrange(start..<start + frames, with: blockL); right.replaceSubrange(start..<start + frames, with: blockR)
            if let heartbeat, Date().timeIntervalSince(lastHeartbeat) >= 1 {
                try Data().write(to: heartbeat, options: .atomic); lastHeartbeat = Date()
            }
        }
        return StereoAudio(left: Array(left.dropFirst(latency)), right: Array(right.dropFirst(latency)), rate: input.rate)
    }

    private static func save(_ audio: StereoAudio, to destination: URL, fileManager fm: FileManager) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".clap-bounce-\(UUID().uuidString).wav")
        defer { try? fm.removeItem(at: temporary) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: audio.rate, channels: 2, interleaved: false)!
        guard audio.left.count <= Int(UInt32.max), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.left.count)), let channels = buffer.floatChannelData else { throw AudioDecodeError.empty }
        buffer.frameLength = buffer.frameCapacity
        audio.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: $0.count) }
        audio.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: $0.count) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: audio.rate, AVNumberOfChannelsKey: 2,
                                       AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false]
        do { let file = try AVAudioFile(forWriting: temporary, settings: settings); try file.write(from: buffer) }
        let check = try AVAudioFile(forReading: temporary)
        guard check.length == Int64(audio.left.count), check.processingFormat.channelCount == 2 else { throw VST3Error.message("The bounce could not be verified. Nothing was saved.") }
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: temporary) }
        else { try fm.moveItem(at: temporary, to: destination) }
    }
}
