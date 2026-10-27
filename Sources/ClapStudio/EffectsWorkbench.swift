import AppKit
import AVFoundation
import ClapCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A reusable bounce recipe, separate from each sample's library edits.
@MainActor @Observable final class EffectsWorkbench: NSObject, NSWindowDelegate {
    var bundles: [URL] = []
    var chain: [EffectSlot] = []
    var samples: [SampleRecord] = []
    var previewID: Int64?
    var tailSeconds = 2.0
    var busy = false
    var scanning = false
    var progress = "" { didSet { if !progress.isEmpty { statusSink?(progress) } } }
    var message: String? { didSet { if let message { errorSink?(message) } } }
    @ObservationIgnored var errorSink: ((String) -> Void)?
    @ObservationIgnored var statusSink: ((String) -> Void)?
    @ObservationIgnored var trims: [Int64: SampleTrim] = [:]
    @ObservationIgnored var protectedSources: [URL] = []
    @ObservationIgnored var panel: NSPanel?
    @ObservationIgnored private var bounceSaved = 0
    @ObservationIgnored private var bounceTotal = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var previewURL: URL?

    func open(samples: [SampleRecord], trims: [Int64: SampleTrim], protectedSources: [URL]) {
        cancel()
        if let sheet = panel?.attachedSheet { panel?.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
        self.samples = samples; self.trims = trims; self.protectedSources = protectedSources
        previewID = samples.first?.id; progress = ""; message = nil
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                                styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "VST3 Effects"; panel.minSize = NSSize(width: 520, height: 420)
            panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true; panel.hidesOnDeactivate = true; panel.delegate = self
            panel.contentView = NSHostingView(rootView: EffectsView(workbench: self))
            panel.center(); self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
        rescan()
    }

    func windowWillClose(_ notification: Notification) { cancel(); scanTask?.cancel() }

    func rescan() {
        scanTask?.cancel(); scanning = true
        scanTask = Task {
            let task = Task.detached { VST3Discovery.bundles() }
            let found = await task.value
            guard !Task.isCancelled else { return }
            bundles = found; scanning = false
        }
    }

    func addBundle(_ bundle: URL) {
        guard !busy else { return }
        do {
            let effects = try VST3Plugin.effects(in: bundle)
            if effects.count == 1, let effect = effects.first { try add(effect) }
            else if effects.isEmpty { message = "No audio effects were found in this bundle." }
            else {
                let menu = NSMenu()
                for effect in effects {
                    let item = NSMenuItem(title: effect.name, action: #selector(addClass(_:)), keyEquivalent: "")
                    item.target = self; item.representedObject = effect; menu.addItem(item)
                }
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        } catch { message = error.localizedDescription }
    }

    @objc private func addClass(_ sender: NSMenuItem) {
        guard let effect = sender.representedObject as? VST3Plugin else { return }
        do { try add(effect) } catch { message = error.localizedDescription }
    }

    private func add(_ effect: VST3Plugin) throws {
        stopPreview()
        chain.append(EffectSlot(plugin: effect, parameters: try effect.parameters()))
        message = nil
    }

    func stopPreview() {
        player?.stop(); player = nil
        if let previewURL { try? FileManager.default.removeItem(at: previewURL) }
        previewURL = nil
    }

    func cancel() {
        let interruptedBounce = busy && bounceTotal > 0
        task?.cancel(); task = nil; stopPreview(); busy = false
        progress = interruptedBounce ? "Cancelled. Bounced \(bounceSaved) of \(bounceTotal) samples; saved copies were kept." : ""
        bounceTotal = 0
    }

    func preview() {
        guard !busy, let sample = samples.first(where: { $0.id == previewID }) else { return }
        stopPreview(); bounceTotal = 0; busy = true; progress = "Rendering preview…"; message = nil
        let recipe = chain, tail = tailSeconds, trim = trims[sample.id]
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("clap-effects-\(UUID().uuidString).wav")
        task = Task {
            do {
                try await EffectBounce.write(source: sample.url, trim: trim, chain: recipe, to: target, tailSeconds: tail)
                try Task.checkCancellation()
                let audio = try AVAudioPlayer(contentsOf: target)
                audio.prepareToPlay()
                guard audio.play() else { throw VST3Error.message("The rendered preview could not start playing.") }
                player = audio; previewURL = target
                busy = false; progress = ""
            } catch {
                try? FileManager.default.removeItem(at: target)
                guard !Task.isCancelled else { return }
                busy = false; progress = ""; message = error.localizedDescription
            }
        }
    }

    func bounce() {
        guard !busy, !samples.isEmpty, let panel else { return }
        stopPreview()
        if samples.count == 1 {
            let save = NSSavePanel()
            save.allowedContentTypes = [.wav]; save.nameFieldStringValue = samples[0].name + " - effects.wav"
            save.beginSheetModal(for: panel) { [weak self] result in
                guard result == .OK, let target = save.url else { return }
                MainActor.assumeIsolated { self?.render(target: target, folder: nil) }
            }
        } else {
            let choose = NSOpenPanel()
            choose.canChooseFiles = false; choose.canChooseDirectories = true; choose.canCreateDirectories = true
            choose.prompt = "Bounce Here"
            choose.beginSheetModal(for: panel) { [weak self] result in
                guard result == .OK, let folder = choose.url else { return }
                MainActor.assumeIsolated { self?.render(target: nil, folder: folder) }
            }
        }
    }

    private func render(target: URL?, folder: URL?) {
        let selected = samples, recipe = chain, savedTrims = trims, tail = tailSeconds, originals = protectedSources
        busy = true; message = nil; bounceSaved = 0; bounceTotal = selected.count
        task = Task {
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
