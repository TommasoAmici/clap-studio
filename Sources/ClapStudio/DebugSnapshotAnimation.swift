#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Records the real shared playback controls as a short, silent loop; only `--native` needs screen capture access.
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
        var images: [CGImage]
        if ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_NATIVE"] == "1" {
            images = try await nativeFrames(started: started, seconds: seconds, frames: frames)
        } else {
            images = []
            for frame in 0..<frames {
                try await ContinuousClock().sleep(until: started.advanced(by: .seconds(Double(frame) * interval)))
                guard let png = DebugSnapshot.windowImage(), let image = NSBitmapImageRep(data: png)?.cgImage else {
                    throw failure("Could not render an animation frame.")
                }
                images.append(image)
            }
        }
        for image in images { CGImageDestinationAddImage(destination, image, properties) }
        guard CGImageDestinationFinalize(destination) else { throw failure("Could not finish the animated capture.") }
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    /// A native capture takes a quarter of a second, longer than a frame. The phrase repeats exactly, so each pass
    /// photographs the frames it can reach and later passes fill the gaps: frame N always shows the same moment.
    private static func nativeFrames(started: ContinuousClock.Instant, seconds: Double, frames: Int) async throws -> [CGImage] {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) else {
            throw failure("Could not find the window to record.")
        }
        let scale = Double(ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_SCALE"] ?? "") ?? 1
        let interval = seconds / Double(frames)
        func elapsed() -> Double {
            let duration = started.duration(to: .now)
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        var images = [CGImage?](repeating: nil, count: frames)
        let giveUpAt = max(60.0, seconds * 20)
        while images.contains(where: { $0 == nil }) {
            guard elapsed() < giveUpAt else { throw failure("Could not record every frame of the playback loop.") }
            // The missing frame that comes up soonest after the current moment in the loop.
            let phase = elapsed().truncatingRemainder(dividingBy: seconds)
            let next = (0..<frames).filter { images[$0] == nil }.min { first, second in
                let a = Double(first) * interval - phase, b = Double(second) * interval - phase
                return (a < 0 ? a + seconds : a) < (b < 0 ? b + seconds : b)
            }!
            let loops = (elapsed() / seconds).rounded(.down)
            var target = loops * seconds + Double(next) * interval
            if target < elapsed() { target += seconds }
            try await ContinuousClock().sleep(until: started.advanced(by: .seconds(target)))
            guard let png = await DebugSnapshot.nativeWindowImageWhileRunning(window),
                  let image = NSBitmapImageRep(data: png)?.cgImage else {
                throw failure("Could not capture an animation frame. The Mac must be awake and unlocked, with screen capture access.")
            }
            images[next] = resized(image, to: window.frame.size, scale: scale)
        }
        return images.compactMap { $0 }
    }

    /// Native captures come at the display's resolution; the GIF uses the requested pixels per point.
    private static func resized(_ image: CGImage, to size: CGSize, scale: Double) -> CGImage {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width != image.width || height != image.height,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ClapSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
