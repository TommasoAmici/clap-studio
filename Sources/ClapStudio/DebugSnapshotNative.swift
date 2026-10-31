#if DEBUG
import AppKit
import CoreGraphics

extension DebugSnapshot {
    /// Captures the window as macOS draws it, glass and toolbar included, at the display's resolution.
    /// `screencapture` renders just this window, without its shadow, even when other windows cover it.
    /// A sheet attached to the window comes with it, in place.
    /// Uses existing screen capture permission; never asks for new access.
    static func nativeWindowImage(_ window: NSWindow) -> Data? {
        guard let (capture, file) = nativeCapture(of: window) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try capture.run()
            capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { return nil }
            return try Data(contentsOf: file)
        } catch { return nil }
    }

    /// The same capture without holding the main thread, so the window keeps drawing (a moving playhead) meanwhile.
    static func nativeWindowImageWhileRunning(_ window: NSWindow) async -> Data? {
        guard let (capture, file) = nativeCapture(of: window) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        let succeeded: Bool = await withCheckedContinuation { continuation in
            capture.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try capture.run() } catch { capture.terminationHandler = nil; continuation.resume(returning: false) }
        }
        return succeeded ? try? Data(contentsOf: file) : nil
    }

    private static func nativeCapture(of window: NSWindow) -> (Process, URL)? {
        guard CGPreflightScreenCaptureAccess() else {
            NSLog("A native window snapshot needs existing macOS screen capture access.")
            return nil
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clap-native-\(UUID()).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        return (capture, file)
    }
}
#endif
