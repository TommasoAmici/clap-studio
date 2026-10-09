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
@MainActor
enum DebugSnapshot {
    static func runIfRequested(model: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["CLAP_SNAPSHOT"] else { return }
        let delay = Double(env["CLAP_SNAPSHOT_DELAY"] ?? "") ?? 9
        try? await Task.sleep(for: .seconds(delay - 3))
        if env["CLAP_SNAPSHOT_MAP"] == "1" { model.viewMode = .map }
        if env["CLAP_SNAPSHOT_SELECT"] == "1" { model.select(model.visible.first?.id, play: false) }
        try? await Task.sleep(for: .seconds(3))
        if let png = windowImage() { try? png.write(to: URL(fileURLWithPath: path)) }
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
