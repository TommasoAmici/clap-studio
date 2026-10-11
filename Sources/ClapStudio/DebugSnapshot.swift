#if DEBUG
import AppKit

/// Development aid: renders the app's window (title bar and toolbar included) to a PNG without needing screen
/// capture permission or the window to be on the current Space. Run it with `scripts/snapshot.sh`.
///
/// Environment (set by the script):
///   CLAP_SNAPSHOT=/path/out.png    write the image, then quit
///   CLAP_SNAPSHOT_DELAY=9          seconds to wait for the library to load (default 9)
///   CLAP_SNAPSHOT_SELECT=1         select the first sample in the list first
///   CLAP_SNAPSHOT_MAP=1            show the Map tab
///   CLAP_PERF=cat.Kick,cat.Snare   switch the sidebar through these tags and log how long the main thread is busy each time
///                                  (to CLAP_PERF_OUT, default /tmp/clap-perf.txt); CLAP_PERF_DELAY waits for loading
///   CLAP_PERF_MAP=1                with CLAP_PERF: do it on the Map tab
///   CLAP_NO_INDEX=1                do not scan or index at launch (for a synthetic library)
///   CLAP_SNAPSHOT_USB=NAME         show the set NAME ("default" for the first one) of the first Squid drive
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
        if env["CLAP_SNAPSHOT_SELECT"] == "1" { model.select(model.visible.first?.id, play: false) }
        if let usb = env["CLAP_SNAPSHOT_USB"], let drive = model.usbDrives.first {
            let set = usb == "default" ? nil : usb
            model.selectSidebar(UsbSelection(drive: drive.id, area: .set(set)).tag)
            if env["CLAP_SNAPSHOT_RENAME"] == "1", let bank = model.usbContents[drive.id]?.set(named: set)?.banks.first {
                model.renamingUsb = .bank(drive: drive.id, set: set, number: bank.number)
            }
        }
        try? await Task.sleep(for: .seconds(3))
        if let png = windowImage() { try? png.write(to: URL(fileURLWithPath: path)) }
        NSApp.terminate(nil)
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
        guard let window = NSApp.windows.first(where: \.isVisible), let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
