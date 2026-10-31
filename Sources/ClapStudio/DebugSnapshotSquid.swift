#if DEBUG
import AppKit
import ClapCore
import SwiftUI

/// Shows the media kit's scratch stick without looking at any connected drive.
@MainActor
enum DebugSnapshotSquid {
    static func prepare(model: AppModel, env: [String: String]) async throws {
        guard env["CLAP_SNAPSHOT"] != nil, env["CLAP_SNAPSHOT_MEDIA"] == "1",
              env["CLAP_SNAPSHOT_USB"] != nil else { return }
        guard let data = env["CLAP_DATA_DIR"], let store = model.store else {
            throw SquidExportError.invalid("Squid media snapshots need a seeded scratch library.")
        }
        let volume = URL(fileURLWithPath: data, isDirectory: true).appendingPathComponent("Squid Demo", isDirectory: true)
        let marker = try String(contentsOf: volume.appendingPathComponent(".clap-media-fixture"), encoding: .utf8)
        guard marker == "media-squid-v1\n" else { throw SquidExportError.invalid("Choose the seeded media library.") }
        let contents = try await Task.detached {
            let cached = try LibraryStore(path: volume.appendingPathComponent(".clap-media.sqlite").path)
            guard cached.meta("media_fixture_version") == "media-squid-v1", cached.loadSamples().count == 54 else {
                throw SquidExportError.invalid("Seed the demonstration stick's sound measurements first.")
            }
            let measurements = Dictionary(uniqueKeysWithValues: cached.loadSamples().map { ($0.relPath, $0) })
            let rootURL = SquidStick.rootURL(volume: volume)
            let root = try store.addRoot(path: rootURL.path, transient: true)
            try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: rootURL)) { path in
                FileFingerprint.compute(url: rootURL.appendingPathComponent(path))
            }
            for sample in store.loadTransientSamples().filter({ $0.rootID == root.id }) {
                guard let source = measurements[sample.relPath], let level = source.loudnessDB,
                      let peak = source.peakDB, let crest = source.crestDB, let centroid = source.centroidHz,
                      let loop = source.isLoop else {
                    throw SquidExportError.invalid("The demonstration stick's cached sound measurements are incomplete.")
                }
                let measured = SoundDescriptors(loudnessDB: level, peakDB: peak, crestDB: crest, centroidHz: centroid,
                                                isLoop: loop, bpm: source.bpm, pitchHz: source.pitchHz, keyName: source.keyName)
                try store.save(results: [.success(id: sample.id, duration: source.duration, sampleRate: source.sampleRate,
                                                  channels: source.channels, embedding: [1, 0, 0, 0], fingerprint: nil,
                                                  modelVersion: "media-squid-v1", descriptors: measured)])
                try store.setManualCategory(sampleID: sample.id, source.effectiveCategory)
            }
            return SquidStick.read(volume: volume)
        }.value
        let drive = UsbDrive(url: volume, name: "SQUID", formatDescription: "MS-DOS (FAT32)", capacity: nil, available: nil)
        model.usbDrives = [drive]
        model.usbContents = [drive.id: contents]
        model.reloadSamples()
    }

    /// Pretends banks 2 to 40 of a set are full (in memory only; the stick is not touched), to show a long list of warnings.
    static func crowd(model: AppModel, driveID: String, set: String?) {
        guard var contents = model.usbContents[driveID] else { return }
        let full = Set(1...SquidLayout.slotsPerBank)
        let banks = (2...40).map { SquidBank(set: set, number: $0, name: "", filled: full) }
        contents.sets.removeAll { SquidLayout.sameSet($0.name, set) }
        contents.sets.insert(SquidSet(name: set, banks: banks), at: 0)
        model.usbContents[driveID] = contents
    }

    /// The Settings view, on its Sidebar tab, in a window of its own that the snapshot can photograph (the real Settings
    /// window cannot be opened from here without a menu click).
    static func showSettings(model: AppModel) {
        UserDefaults.standard.set(SettingsTab.sidebar.rawValue, forKey: SettingsTab.storageKey)
        let controller = NSHostingController(rootView: SettingsView().environment(model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Keeps the selected stick and its folders visible in a long sidebar.
    static func revealSidebar() {
        guard let window = NSApp.windows.first(where: \.isVisible), let content = window.contentView else { return }
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView,
               scroll.convert(scroll.bounds, to: content).minX < 10, scroll.bounds.width < 300,
               scroll.documentView != nil { return scroll }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        guard let scroll = find(content), let document = scroll.documentView else { return }
        let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
#endif
