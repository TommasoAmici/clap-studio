#if DEBUG
import AppKit
import ClapCore

/// Development aid: renders the app's window (title bar and toolbar included) to a PNG without needing screen
/// capture permission or the window to be on the current Space. Run it with `scripts/snapshot.sh`.
///
/// Environment (set by the script):
///   CLAP_SNAPSHOT=/path/out.png    write the image, then quit
///   CLAP_SNAPSHOT_DELAY=9          seconds to wait for the library to load (default 9)
///   CLAP_SNAPSHOT_SELECT=1         select the first sample in the list first
///   CLAP_SNAPSHOT_MAP=1            show the Map tab
///   CLAP_SNAPSHOT_EDIT=1           with SELECT: give the selected sample a sample edit (changes the library: use a copy)
///   CLAP_PERF=cat.Kick,cat.Snare   switch the sidebar through these tags and log how long the main thread is busy each time
///                                  (to CLAP_PERF_OUT, default /tmp/clap-perf.txt); CLAP_PERF_DELAY waits for loading
///   CLAP_PERF_MAP=1                with CLAP_PERF: do it on the Map tab
///   CLAP_NO_INDEX=1                do not scan or index at launch (for a synthetic library)
///   CLAP_SNAPSHOT_USB=NAME         show the set NAME ("default" for the first one) of the first Squid drive; NAME/2 shows its bank 2;
///                                  "pool" shows the Pool and "pool/Breaks/707" one of its folders
///   CLAP_SNAPSHOT_CLOSE=Breaks/707 with USB: fold that Pool folder shut
///   CLAP_SNAPSHOT_SEND=Breaks   with USB: open the Send sheet for that Pool folder ("-" for the Pool itself)
///   CLAP_SNAPSHOT_DRUMS=1          open the drum machine with the first three samples
///   CLAP_SNAPSHOT_MELODY=1         open the melody with the first two samples and a few notes
///   CLAP_SNAPSHOT_MELODY_BARS=N    with the above: repeat the notes every two bars up to N bars
///   CLAP_SNAPSHOT_LIKE=name        show sounds like the first sample whose name contains this; CLAP_SNAPSHOT_WORDS adds words ("dark, no reverb")
///   CLAP_SNAPSHOT_PLACES=1         show the Places tab
///   CLAP_SNAPSHOT_NO_INSPECTOR=1   start with the inspector hidden
///   CLAP_SNAPSHOT_WIDTH=1100       resize the window to this width first (it cannot go below the window's minimum)
///   CLAP_SNAPSHOT_RENAME=1         with USB: put the first bank's name in edit mode
@MainActor
enum DebugSnapshot {
    static func runIfRequested(model: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        if let tags = env["CLAP_PERF"] { await perf(model: model, tags: tags.split(separator: ",").map(String.init), env: env); return }
        guard let path = env["CLAP_SNAPSHOT"] else { return }
        let delay = Double(env["CLAP_SNAPSHOT_DELAY"] ?? "") ?? 9
        try? await Task.sleep(for: .seconds(delay - 3))
        if env["CLAP_SNAPSHOT_MAP"] == "1" { model.viewMode = .map }
        if env["CLAP_SNAPSHOT_PLACES"] == "1" { model.viewMode = .places }
        if env["CLAP_SNAPSHOT_DRUMS"] == "1" {
            model.addToDrums(Array(model.visible.prefix(3).map(\.id)))
            if let bars = env["CLAP_SNAPSHOT_DRUM_BARS"].flatMap(Int.init) { model.drumPattern.setBars(bars) }
            if let bar = env["CLAP_SNAPSHOT_DRUM_BAR"].flatMap(Int.init) {
                model.drumBar = min(max(bar - 1, 0), model.drumPattern.bars - 1)
            }
        }
        if let midi = env["CLAP_SNAPSHOT_DRUM_MIDI"],
           let song = try? await Task.detached(operation: { try DrumImport.read(url: URL(fileURLWithPath: midi)) }).value {
            model.drumPattern = DrumPattern()
            model.select(model.visible.first?.id, play: false)
            model.applyDrumMidi(song, named: URL(fileURLWithPath: midi).lastPathComponent, setTempo: false)
        }
        if env["CLAP_SNAPSHOT_MELODY"] == "1" { sketchMelody(model) }
        if let like = env["CLAP_SNAPSHOT_LIKE"], let sample = model.samples.first(where: { $0.name.contains(like) }) {
            model.showSimilar(to: sample.id)
            if let words = env["CLAP_SNAPSHOT_WORDS"] { try? await Task.sleep(for: .seconds(1)); model.refinementText = words; try? await Task.sleep(for: .seconds(3)) }
            if env["CLAP_SNAPSHOT_LOG"] == "1" { NSLog("SNAPSHOT-ORDER %@", model.visible.prefix(8).map(\.name).joined(separator: ", ")) }
        }
        if env["CLAP_SNAPSHOT_SELECT"] == "1" { model.select(model.visible.first?.id, play: false) }
        if env["CLAP_SNAPSHOT_EDIT"] == "1" { model.setEdit(SampleEdit(reverse: true, gainDB: -3, lowPassHz: 4000), audition: false) }
        if let usb = env["CLAP_SNAPSHOT_USB"], let drive = model.usbDrives.first {
            // "NAME" is a set ("default" for the first one), "NAME/2" is that set's bank 2.
            let parts = usb.split(separator: "/", maxSplits: 1).map(String.init)
            let set = parts.first == "default" ? nil : parts.first
            var area: UsbSelection.Area = parts.count == 2 ? .bank(set: set, number: Int(parts[1]) ?? 1) : .set(set)
            // "pool" is the Pool, "pool/Breaks/707" a folder of it.
            if parts.first == "pool" { area = parts.count == 2 ? .poolFolder(parts[1].split(separator: "/").map(String.init)) : .pool }
            model.selectSidebar(UsbSelection(drive: drive.id, area: area).tag)
            // "Breaks/707" folds that Pool folder shut.
            if let closed = env["CLAP_SNAPSHOT_CLOSE"] { model.togglePoolFolder(drive: drive.id, path: closed.split(separator: "/").map(String.init)) }
            // Opens the Send sheet for the Pool folder NAME ("-" for the Pool itself) with the first two samples shown.
            if let send = env["CLAP_SNAPSHOT_SEND"] {
                try? await Task.sleep(for: .seconds(1))
                model.openSquidExport(ids: Array(model.visible.prefix(2).map(\.id)), drive: drive.id, pool: true, poolFolder: send == "-" ? "" : send)
            }
            if env["CLAP_SNAPSHOT_RENAME"] == "1", let bank = model.usbContents[drive.id]?.set(named: set)?.banks.first {
                model.renamingUsb = .bank(drive: drive.id, set: set, number: bank.number)
            }
        }
        if let width = Double(env["CLAP_SNAPSHOT_WIDTH"] ?? ""), let window = NSApp.windows.first(where: \.isVisible) {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
        }
        try? await Task.sleep(for: .seconds(3))
        if let png = windowImage() { try? png.write(to: URL(fileURLWithPath: path)) }
        NSApp.terminate(nil)
    }

    /// Two melody tracks from the first two samples with a few bars of notes, so the piano roll has something to show.
    private static func sketchMelody(_ model: AppModel) {
        model.addToMelody(Array(model.visible.prefix(2).map(\.id)))
        let bars = max(2, Int(ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_MELODY_BARS"] ?? "") ?? 2)
        var pattern = model.melodyPattern
        pattern.setBars(bars)
        let lead: [(Int, Double, Double)] = [(64, 0, 2), (67, 2, 2), (72, 4, 4), (71, 8, 2), (67, 10, 2), (64, 12, 4),
                                             (65, 16, 2), (69, 18, 2), (74, 20, 4), (72, 24, 4), (67, 28, 4)]
        for section in 0..<(bars / 2) {
            let shift = Double(section * 32)
            for n in lead { pattern.addNote(track: 0, pitch: n.0, start: n.1 + shift, length: n.2, velocity: 0.85) }
            if pattern.tracks.count > 1 {
                for (i, pitch) in [48, 48, 43, 41].enumerated() { pattern.addNote(track: 1, pitch: pitch, start: Double(i * 8) + shift, length: 6) }
            }
        }
        model.melodyPattern = pattern
        model.selectedMelodyTrack = 0
    }

    /// Sidebar switching, timed: the work done in the click itself, then how long the main thread stays too busy to
    /// answer a 20 ms timer (a beach ball is that, for long enough).
    private static func perf(model: AppModel, tags: [String], env: [String: String]) async {
        let out = env["CLAP_PERF_OUT"] ?? "/tmp/clap-perf.txt"
        var log = "samples: \(model.samples.count)\n"
        try? await Task.sleep(for: .seconds(Double(env["CLAP_PERF_DELAY"] ?? "") ?? 30))
        if env["CLAP_PERF_MAP"] == "1" { model.viewMode = .map; try? await Task.sleep(for: .seconds(3)) }
        log += "after wait: samples \(model.samples.count), visible \(model.visible.count)\n"
        for round in 0..<2 {
            for tag in tags {
                let t0 = CFAbsoluteTimeGetCurrent()
                model.selectSidebar(tag)
                let click = CFAbsoluteTimeGetCurrent() - t0
                var busy = 0.0, worst = 0.0
                let start = CFAbsoluteTimeGetCurrent()
                while CFAbsoluteTimeGetCurrent() - start < 4 {
                    let t = CFAbsoluteTimeGetCurrent()
                    try? await Task.sleep(for: .milliseconds(20))
                    let late = max(0, CFAbsoluteTimeGetCurrent() - t - 0.02)
                    busy += late; worst = max(worst, late)
                }
                log += String(format: "round %d %@: click %.0f ms, then busy %.0f ms (worst stall %.0f ms), visible %d\n",
                              round, tag, click * 1000, busy * 1000, worst * 1000, model.visible.count)
                try? log.write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        NSApp.terminate(nil)
    }

    /// The frame view holds the toolbar as well as the content.
    private static func windowImage() -> Data? {
        // A sheet is a window of its own: when one is open, it is what gets drawn.
        guard let main = NSApp.windows.first(where: \.isVisible), let window = Optional(main.attachedSheet ?? main), let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
