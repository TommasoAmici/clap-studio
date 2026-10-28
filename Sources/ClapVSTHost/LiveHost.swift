import AppKit
import AVFoundation
import ClapCore

/// A warm helper queues short blocks, with editor and processor on its serial run loop.
@MainActor final class LiveHost {
    private let request: VST3HostRequest
    private let directory: URL
    private let processor: VST3LiveProcessor
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var timer: Timer?
    private var continuation: CheckedContinuation<VST3HostReply, any Error>?
    private var input: AVAudioPCMBuffer?
    private var position = 0
    private var totalFrames = 0
    private var scheduledFrames = 0
    private var sampleID: Int64?
    private var duration: Double = 0
    private var previousRecipe: [EffectSlot]?
    private var previousParameters: [[VST3Parameter]] = []
    private var generation = UUID()
    private var decodeTask: Task<Void, Never>?
    private var lastPlay: VST3LiveCommand?
    private var editorTask: Task<Void, Never>?
    private var editorID: UUID?
    private var editorWindow: NSWindow?
    private var lastHeartbeat = Date.distantPast

    static func run(_ request: VST3HostRequest) async throws -> VST3HostReply {
        let host = try LiveHost(request)
        return try await withCheckedThrowingContinuation { host.continuation = $0; host.start() }
    }

    private init(_ request: VST3HostRequest) throws {
        guard let directory = request.sessionDirectory, let chain = request.chain else {
            throw VST3Error.message("Missing live effects chain.")
        }
        self.request = request; self.directory = directory
        processor = try VST3LiveProcessor(chain: chain, sampleRate: 44_100)
        engine.attach(player); engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        timePitch.bypass = true
    }

    private func start() {
        previousRecipe = try? processor.snapshot()
        previousParameters = processor.parameterValues()
        publish(VST3LiveStatus(chain: previousRecipe))
        let timer = Timer(timeInterval: 0.005, repeats: true) { [self] _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        self.timer = timer
    }

    private func tick() {
        do {
            if Date().timeIntervalSince(lastHeartbeat) >= 0.5 {
                if let heartbeat = request.heartbeat { try Data().write(to: heartbeat, options: .atomic) }
                lastHeartbeat = Date()
                if editorID != nil {
                    let parameters = processor.parameterValues()
                    if parameters != previousParameters {
                        previousParameters = parameters
                        let recipe = try processor.snapshot()
                        previousRecipe = recipe
                        publish(VST3LiveStatus(sampleID: sampleID, duration: duration, chain: recipe, playbackToken: sampleID == nil ? nil : generation))
                    }
                }
            }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { VST3LiveFiles.isCommand($0.lastPathComponent) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                let data = try Data(contentsOf: file)
                guard data.count <= 64 * 1024 * 1024 else { throw VST3Error.message("The preview command is too large.") }
                let command = try JSONDecoder().decode(VST3LiveCommand.self, from: data)
                try FileManager.default.removeItem(at: file)
                try handle(command)
            }
            try pump()
        } catch {
            stop(); timer?.invalidate(); timer = nil
            publish(VST3LiveStatus(error: error.localizedDescription))
            continuation?.resume(returning: VST3HostReply(error: error.localizedDescription)); continuation = nil
        }
    }

    private func handle(_ command: VST3LiveCommand) throws {
        switch command.operation {
        case .stop: stop(); publish(VST3LiveStatus())
        case .play: play(command)
        case .closeEditor: editorWindow?.performClose(nil)
        case .volume: engine.mainMixerNode.outputVolume = min(1, max(0, command.volume))
        case .snapshot:
            guard let id = command.requestID else { throw VST3Error.message("Missing settings request.") }
            let status = VST3LiveStatus(sampleID: sampleID, duration: duration, chain: try processor.snapshot(),
                                       requestID: id, playbackToken: sampleID == nil ? nil : generation)
            try JSONEncoder().encode(status).write(to: directory.appendingPathComponent("reply-\(id).json"), options: .atomic)
        case .update:
            if let chain = command.chain {
                try processor.update(chain)
                // A longer tail must also extend a sample already being auditioned.
                if let input, let play = lastPlay {
                    let extra = play.tailSeconds.isFinite ? min(10, max(0, play.tailSeconds)) : 2
                    let revised = Int(input.frameLength) + max(processor.tailFrames, Int(format.sampleRate * extra))
                    if revised > totalFrames {
                        totalFrames = revised
                        duration = Double(totalFrames) / format.sampleRate / Double(play.rate)
                        publish(VST3LiveStatus(sampleID: sampleID, duration: duration, playbackToken: generation))
                    }
                }
            }
        case .edit:
            guard editorTask == nil, let id = command.effectID else { return }
            let session = try processor.editor(for: id)
            editorID = id
            editorTask = Task { [self] in
                do {
                    var editorRequest = VST3HostRequest(operation: .editor, slot: try session.snapshot())
                    editorRequest.heartbeat = request.heartbeat
                    #if DEBUG
                    editorRequest.editorCloseAfter = request.editorCloseAfter
                    editorRequest.editorSnapshot = request.editorSnapshot
                    #endif
                    _ = try await NativeEditor.run(editorRequest, session: session,
                                                   preview: { [weak self] in self?.replay() }, stop: { [weak self] in self?.stop(); self?.publish(VST3LiveStatus()) },
                                                   windowSink: { [weak self] in self?.editorWindow = $0 })
                    publish(VST3LiveStatus(sampleID: sampleID, duration: duration, chain: try processor.snapshot(),
                                           playbackToken: sampleID == nil ? nil : generation))
                } catch { publish(VST3LiveStatus(sampleID: sampleID, error: error.localizedDescription)) }
                editorTask = nil; editorID = nil; editorWindow = nil
            }
        }
    }

    private func replay() { if let lastPlay { play(lastPlay) } }

    private func play(_ command: VST3LiveCommand) {
        stop(); lastPlay = command
        guard let source = command.source else { return }
        let token = generation, trim = command.trim, format = format
        decodeTask = Task {
            do {
                let decode = Task.detached(priority: .userInitiated) {
                    try TrimRender.read(url: source, start: trim?.start ?? 0, end: trim?.end,
                                        fadeIn: trim == nil ? 0 : SampleTrim.declick,
                                        fadeOut: trim?.effectiveFadeOut ?? 0, edit: trim?.edit,
                                        convertTo: format, maxSeconds: 300)
                }
                let buffer = try await withTaskCancellationHandler(operation: { try await decode.value }, onCancel: { decode.cancel() })
                guard !Task.isCancelled, generation == token else { return }
                input = buffer; position = 0; scheduledFrames = 0
                let extra = command.tailSeconds.isFinite ? min(10, max(0, command.tailSeconds)) : 2
                totalFrames = Int(buffer.frameLength) + max(processor.tailFrames, Int(format.sampleRate * extra))
                sampleID = command.sampleID
                timePitch.rate = command.rate; timePitch.pitch = command.pitchCents
                timePitch.bypass = command.rate == 1 && command.pitchCents == 0
                player.volume = pow(10, command.gainDB / 20)
                engine.mainMixerNode.outputVolume = min(1, max(0, command.volume))
                if !engine.isRunning { engine.prepare(); try engine.start() }
                try pump()
                player.play()
                duration = Double(totalFrames) / format.sampleRate / Double(command.rate)
                publish(VST3LiveStatus(sampleID: sampleID, duration: duration, playbackToken: generation))
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                stop(); publish(VST3LiveStatus(error: error.localizedDescription))
            }
        }
    }

    private func pump() throws {
        guard let input, let channels = input.floatChannelData, position < totalFrames else { return }
        let played: Int
        if let time = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: time) {
            played = max(0, Int(playerTime.sampleTime))
        } else { played = 0 }
        // Bound work and queue about 40 ms, even when a long sample is selected.
        let target = played + Int(format.sampleRate * 0.04)
        for _ in 0..<8 where scheduledFrames < target && position < totalFrames {
            let count = min(512, totalFrames - position)
            var left = [Float](repeating: 0, count: count), right = left
            let available = max(0, min(count, Int(input.frameLength) - position))
            if available > 0 {
                left.replaceSubrange(0..<available, with: UnsafeBufferPointer(start: channels[0] + position, count: available))
                right.replaceSubrange(0..<available, with: UnsafeBufferPointer(start: channels[1] + position, count: available))
            }
            try processor.process(left: &left, right: &right)
            #if DEBUG
            if position == 0, let output = request.liveSnapshot {
                try JSONEncoder().encode([left, right]).write(to: output, options: .atomic)
            }
            #endif
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let output = buffer.floatChannelData else { throw AudioDecodeError.empty }
            buffer.frameLength = buffer.frameCapacity
            left.withUnsafeBufferPointer { output[0].update(from: $0.baseAddress!, count: count) }
            right.withUnsafeBufferPointer { output[1].update(from: $0.baseAddress!, count: count) }
            position += count; scheduledFrames += count
            let token = generation, final = position == totalFrames, finalFrames = totalFrames
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard final else { return }
                Task { @MainActor in
                    guard let self, self.generation == token, self.totalFrames == finalFrames else { return }
                    self.input = nil; self.sampleID = nil; self.publish(VST3LiveStatus())
                }
            }
        }
    }

    private func stop() {
        generation = UUID(); decodeTask?.cancel(); decodeTask = nil
        player.stop(); input = nil; sampleID = nil; position = 0; scheduledFrames = 0
    }

    private func publish(_ status: VST3LiveStatus) {
        try? JSONEncoder().encode(status).write(to: directory.appendingPathComponent("status.json"), options: .atomic)
    }
}
