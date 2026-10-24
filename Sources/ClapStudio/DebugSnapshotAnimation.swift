#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Records the real shared playback controls as a short, silent loop without screen capture access.
@MainActor
enum DebugSnapshotAnimation {
    static func write(model: AppModel, to url: URL) async throws {
        guard model.showDrums || model.showMelody else { throw failure("Open drums or melody to record playback.") }
        let frames = 48
        let seconds = 60 / min(300, max(30, model.drumTempo)) * 8
        let interval = seconds / Double(frames)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".clap-animation-\(UUID()).gif")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.gif.identifier as CFString,
                                                                frames, nil) else {
            throw failure("Could not create the animated capture.")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let properties = [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFDelayTime as String: interval]] as CFDictionary
        model.toggleDrumPlayback()
        defer { model.drumMachine.stop() }
        let readyBy = ContinuousClock.now.advanced(by: .seconds(3))
        while !model.drumPlaying || model.melodyStep == nil {
            guard ContinuousClock.now < readyBy else { throw failure("Playback did not start for the animated capture.") }
            try await Task.sleep(for: .milliseconds(5))
        }
        let started = ContinuousClock.now
        for frame in 0..<frames {
            let deadline = started.advanced(by: .seconds(Double(frame) * interval))
            try await ContinuousClock().sleep(until: deadline)
            guard let png = DebugSnapshot.windowImage(), let image = NSBitmapImageRep(data: png)?.cgImage else {
                throw failure("Could not render an animation frame.")
            }
            CGImageDestinationAddImage(destination, image, properties)
        }
        guard CGImageDestinationFinalize(destination) else { throw failure("Could not finish the animated capture.") }
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ClapSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
