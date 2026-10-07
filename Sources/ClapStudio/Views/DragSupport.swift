import AppKit
import ClapCore
import SwiftUI
import UniformTypeIdentifiers

/// Pasteboard payload for dragging a sample file into a DAW. The original file URL is
/// offered (public.file-url) so the DAW references or copies the file in place.
enum SampleDrag {
    static func provider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        if let type = UTType(filenameExtension: url.pathExtension) {
            provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [.openInPlace],
                                                visibility: .all) { completion in
                completion(url, true, nil)
                return nil
            }
        }
        provider.suggestedName = url.deletingPathExtension().lastPathComponent
        return provider
    }
}

extension View {
    /// Makes a SwiftUI row draggable and counts the grab when the drag starts.
    func sampleDrag(_ sample: SampleRecord, model: AppModel) -> some View {
        onDrag {
            MainActor.assumeIsolated { model.registerGrab(sample.id) }
            return SampleDrag.provider(for: sample.url)
        } preview: {
            Label(sample.name, systemImage: "waveform").padding(8).background(.regularMaterial, in: Capsule())
        }
    }
}

/// An AppKit drag source used for the inspector's "drag to your DAW" handle.
struct FileDragHandle: NSViewRepresentable {
    let url: URL
    let title: String
    let onBegin: () -> Void

    func makeNSView(context: Context) -> DragHandleNSView {
        let v = DragHandleNSView()
        v.configure(url: url, title: title, onBegin: onBegin)
        return v
    }

    func updateNSView(_ view: DragHandleNSView, context: Context) {
        view.configure(url: url, title: title, onBegin: onBegin)
    }
}

final class DragHandleNSView: NSView, NSDraggingSource {
    private var url: URL?
    private var title = ""
    private var onBegin: () -> Void = {}
    private var mouseDownPoint: NSPoint?

    func configure(url: URL, title: String, onBegin: @escaping () -> Void) {
        self.url = url; self.title = title; self.onBegin = onBegin
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 44) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1; path.setLineDash([4, 3], count: 2, phase: 0); path.stroke()
        let text = "Drag into Ableton or any DAW" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                    .foregroundColor: NSColor.labelColor]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let url,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        onBegin()
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
