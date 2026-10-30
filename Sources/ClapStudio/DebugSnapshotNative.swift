#if DEBUG
import AppKit
import CoreGraphics

extension DebugSnapshot {
    /// Captures the window as macOS draws it, glass and toolbar included, at the display's resolution.
    /// `screencapture` renders just this window, without its shadow, even when other windows cover it.
    /// A sheet attached to the window comes with it, in place.
    /// Uses existing screen capture permission; never asks for new access.
    static func nativeWindowImage(_ window: NSWindow) -> Data? {
        guard CGPreflightScreenCaptureAccess() else {
            NSLog("A native window snapshot needs existing macOS screen capture access.")
            return nil
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clap-native-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        do {
            try capture.run()
            capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { return nil }
            return try Data(contentsOf: file)
        } catch { return nil }
    }
}
#endif
