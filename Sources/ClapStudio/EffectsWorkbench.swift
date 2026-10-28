import AppKit
import ClapCore
import Observation
import UniformTypeIdentifiers

/// A reusable effects chain for auditions and independent bounced copies.
@MainActor @Observable final class EffectsWorkbench: NSObject {
    var isOpen = false
    var bundles: [URL] = []
    var chain: [EffectSlot] = [] { didSet { if !receivingSettings { synchronizeChain(from: oldValue) } } }
    var samples: [SampleRecord] = []
    var previewID: Int64?
    var enabled = true { didSet { if !enabled { stopPreview() } } }
    var tailSeconds = 2.0
    var busy = false
    var scanning = false
    var progress = "" { didSet { if !progress.isEmpty { statusSink?(progress) } } }
    var message: String? { didSet { if let message { errorSink?(message) } } }
    @ObservationIgnored var errorSink: ((String) -> Void)?
    @ObservationIgnored var statusSink: ((String) -> Void)?
    @ObservationIgnored var playbackSink: ((PlaybackState) -> Void)?
    @ObservationIgnored var previewSink: ((SampleRecord) -> Void)?
    @ObservationIgnored var trims: [Int64: SampleTrim] = [:]
    @ObservationIgnored var protectedSources: [URL] = []
    @ObservationIgnored private var bounceSaved = 0
    @ObservationIgnored private var bounceTotal = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let live = VST3LiveClient()
    @ObservationIgnored private var receivingSettings = false
    @ObservationIgnored private var playingID: Int64?
    @ObservationIgnored private var playingToken: UUID?

    func open(samples: [SampleRecord], trims: [Int64: SampleTrim], protectedSources: [URL]) {
        refresh(samples: samples, trims: trims, protectedSources: protectedSources)
        message = nil
        if bundles.isEmpty { rescan() }
        prepareLive()
    }

    func refresh(samples: [SampleRecord], trims: [Int64: SampleTrim], protectedSources: [URL]? = nil) {
        self.samples = samples; self.trims = trims
        if let protectedSources { self.protectedSources = protectedSources }
        previewID = samples.first?.id
    }

    func rescan() {
        scanTask?.cancel(); scanning = true
        scanTask = Task {
            let scan = Task.detached { VST3Discovery.bundles() }
            let found = await scan.value
            guard !Task.isCancelled else { return }
            bundles = found; scanning = false
        }
    }

    func addBundle(_ bundle: URL) {
        guard !busy else { return }
        busy = true; progress = "Loading effect…"; message = nil
        task = Task {
            do {
                let effects = try await VST3Plugin.effects(in: bundle)
                try Task.checkCancellation()
                busy = false; progress = ""
                if effects.count == 1, let effect = effects.first { add(effect) }
                else if effects.isEmpty { message = "No audio effects were found in this bundle." }
                else {
                    let menu = NSMenu()
                    for effect in effects {
                        let item = NSMenuItem(title: effect.name, action: #selector(addClass(_:)), keyEquivalent: "")
                        item.target = self; item.representedObject = effect; menu.addItem(item)
                    }
                    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                }
            } catch {
                guard !Task.isCancelled else { return }
                busy = false; progress = ""; message = error.localizedDescription
            }
        }
    }

    @objc private func addClass(_ sender: NSMenuItem) {
        guard !busy, let effect = sender.representedObject as? VST3Plugin else { return }
        add(effect)
    }

    private func add(_ effect: VST3Plugin) {
        busy = true; progress = "Loading effect…"; message = nil
        task = Task {
            do {
                let slot = try await effect.makeSlot()
                try await rememberLiveSettings()
                try Task.checkCancellation()
                busy = false; progress = ""; chain.append(slot)
            } catch {
                guard !Task.isCancelled else { return }
                busy = false; progress = ""; message = error.localizedDescription
            }
        }
    }

    func removeEffect(_ id: UUID) {
        changeChain { [self] in chain.removeAll { $0.id == id } }
    }

    func moveEffect(_ id: UUID, by offset: Int) {
        changeChain { [self] in
            guard let index = chain.firstIndex(where: { $0.id == id }), chain.indices.contains(index + offset) else { return }
            chain.swapAt(index, index + offset)
        }
    }

    private func changeChain(_ action: @escaping @MainActor () -> Void) {
        guard !busy else { return }
        busy = true
        task = Task {
            do {
                try await rememberLiveSettings()
                try Task.checkCancellation()
                action(); busy = false
            } catch {
                guard !Task.isCancelled else { return }
                busy = false; message = error.localizedDescription
            }
        }
    }

    private func rememberLiveSettings() async throws {
        guard live.isRunning else { return }
        let recipe = try await live.snapshot()
        try Task.checkCancellation()
        guard recipe.map(\.id) == chain.map(\.id) else { return }
        receivingSettings = true; chain = recipe; receivingSettings = false
    }

    func closeDrawer() {
        cancel()
        if live.isRunning { send(VST3LiveCommand(operation: .closeEditor)) }
    }

    func edit(_ id: UUID) {
        guard !busy, chain.contains(where: { $0.id == id }) else { return }
        prepareLive()
        var command = VST3LiveCommand(operation: .edit); command.effectID = id
        send(command)
    }

    func audition(_ sample: SampleRecord, trim: SampleTrim?, rate: Float, pitchCents: Float, gainDB: Float, volume: Float) {
        prepareLive()
        var command = VST3LiveCommand(operation: .play)
        command.source = sample.url; command.sampleID = sample.id; command.trim = trim
        command.rate = rate; command.pitchCents = pitchCents; command.gainDB = gainDB
        command.volume = volume; command.tailSeconds = tailSeconds
        send(command)
    }

    private func prepareLive() {
        guard !chain.isEmpty, !live.isRunning else { return }
        live.onStatus = { [weak self] status in
            guard let self else { return }
            if let recipe = status.chain, recipe.map(\.id) == chain.map(\.id) {
                receivingSettings = true; chain = recipe; receivingSettings = false
            }
            if isOpen && enabled && (status.playbackToken != playingToken || status.sampleID != playingID) {
                playingToken = status.playbackToken; playingID = status.sampleID
                playbackSink?(PlaybackState(sampleID: status.sampleID, startedAt: status.sampleID == nil ? nil : Date(),
                                            duration: status.duration, tracksPlayhead: false))
            }
            if let error = status.error {
                message = error; playingToken = nil; playingID = nil
                if isOpen && enabled { playbackSink?(PlaybackState()) }
            }
        }
        do { try live.start(chain: chain) } catch { message = error.localizedDescription }
    }

    private func synchronizeChain(from previous: [EffectSlot]) {
        if chain.isEmpty { suspend(); return }
        if previous.map(\.id) != chain.map(\.id) || zip(previous, chain).contains(where: { $0.plugin != $1.plugin }) {
            suspend(); prepareLive()
        } else {
            prepareLive()
            var command = VST3LiveCommand(operation: .update)
            command.chain = chain.map { slot in
                var slot = slot; slot.componentState = nil; slot.controllerState = nil
                return slot
            }
            send(command)
        }
    }

    private func send(_ command: VST3LiveCommand) {
        do { try live.send(command) } catch { message = error.localizedDescription }
    }

    func setVolume(_ volume: Float) {
        guard live.isRunning else { return }
        var command = VST3LiveCommand(operation: .volume); command.volume = volume
        send(command)
    }

    func stopPreview() {
        if live.isRunning { send(VST3LiveCommand(operation: .stop)) }
        playingToken = nil; playingID = nil; playbackSink?(PlaybackState())
    }

    func suspend() { live.close(); playingToken = nil; playingID = nil; playbackSink?(PlaybackState()) }

    func cancel() {
        let interruptedBounce = busy && bounceTotal > 0
        task?.cancel(); task = nil; stopPreview(); busy = false
        progress = interruptedBounce ? "Cancelled. Bounced \(bounceSaved) of \(bounceTotal) samples; saved copies were kept." : ""
        bounceTotal = 0
    }

    func preview() {
        guard let sample = samples.first(where: { $0.id == previewID }) ?? samples.first else { return }
        previewSink?(sample)
    }

    func bounce() {
        guard !busy, !samples.isEmpty, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        stopPreview()
        if samples.count == 1 {
            let save = NSSavePanel()
            save.allowedContentTypes = [.wav]; save.nameFieldStringValue = samples[0].name + " - effects.wav"
            save.beginSheetModal(for: window) { [weak self] result in
                guard result == .OK, let target = save.url else { return }
                MainActor.assumeIsolated { self?.render(target: target, folder: nil) }
            }
        } else {
            let choose = NSOpenPanel()
            choose.canChooseFiles = false; choose.canChooseDirectories = true; choose.canCreateDirectories = true
            choose.prompt = "Bounce Here"
            choose.beginSheetModal(for: window) { [weak self] result in
                guard result == .OK, let folder = choose.url else { return }
                MainActor.assumeIsolated { self?.render(target: nil, folder: folder) }
            }
        }
    }

    private func render(target: URL?, folder: URL?) {
        let selected = samples, savedTrims = trims, tail = tailSeconds, originals = protectedSources
        busy = true; message = nil; bounceSaved = 0; bounceTotal = selected.count
        task = Task {
            let recipe: [EffectSlot]
            do {
                recipe = live.isRunning ? try await live.snapshot() : chain
                try Task.checkCancellation()
            } catch {
                guard !Task.isCancelled else { return }
                busy = false; bounceTotal = 0; message = error.localizedDescription
                return
            }
            var saved = 0, failureCount = 0, failures: [String] = []
            for sample in selected {
                if Task.isCancelled { break }
                progress = "Bouncing \(saved + failureCount + 1) of \(selected.count)…"
                let destination = target ?? SampleExporter.uniqueURL(in: folder!, fileName: sample.name + " - effects.wav")
                do {
                    try await EffectBounce.write(source: sample.url, trim: savedTrims[sample.id], chain: recipe, to: destination,
                                                 tailSeconds: tail, protectedSources: originals)
                    try Task.checkCancellation()
                    saved += 1; bounceSaved = saved
                } catch {
                    if Task.isCancelled { break }
                    failureCount += 1
                    if failures.count < 10 { failures.append("\(sample.name): \(error.localizedDescription)") }
                }
            }
            guard !Task.isCancelled else { return }
            busy = false; bounceTotal = 0; progress = "Bounced \(saved) of \(selected.count) samples."
            message = failureCount == 0 ? nil : failures.joined(separator: "\n") + (failureCount > 10 ? "\n… and \(failureCount - 10) more failures." : "")
        }
    }
}
