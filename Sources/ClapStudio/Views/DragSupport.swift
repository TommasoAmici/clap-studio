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

/// Reads the file URLs out of dropped item providers and hands them over on the main actor.
enum DroppedFiles {
    static func load(from providers: [NSItemProvider], perform: @escaping @MainActor ([URL]) -> Void) -> Bool {
        let accepting = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !accepting.isEmpty else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var found: [URL] = []
        for provider in accepting {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); found.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = found
            MainActor.assumeIsolated { perform(urls) }
        }
        return true
    }
}

extension View {
    /// Accepts file drags (from the library list, the kit builder, the tray, or Finder) and hands over their URLs.
    /// Highlights through `isTargeted` while a drag is over the view.
    func fileDrop(isTargeted: Binding<Bool>? = nil, perform: @escaping @MainActor ([URL]) -> Void) -> some View {
        onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in DroppedFiles.load(from: providers, perform: perform) }
    }
}

// MARK: one window-wide drop target

/// Places inside the window that take dropped files. Nested drop targets are unreliable on macOS, so the window has
/// a single one and finds the place under the pointer from these frames.
enum DropZone: Hashable {
    case drumTrack(Int)
    case drums
}

struct DropZoneFrames: PreferenceKey {
    static let defaultValue: [DropZone: CGRect] = [:]
    static func reduce(value: inout [DropZone: CGRect], nextValue: () -> [DropZone: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

let dropCoordinateSpace = "windowDrop"

extension View {
    func dropZone(_ zone: DropZone) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: DropZoneFrames.self, value: [zone: proxy.frame(in: .named(dropCoordinateSpace))])
        })
    }
}

struct WindowDropDelegate: DropDelegate {
    let model: AppModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) { model.dropHover = model.dropZone(at: info.location) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let zone = model.dropZone(at: info.location)
        if zone != model.dropHover { model.dropHover = zone }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { model.dropHover = nil }

    func performDrop(info: DropInfo) -> Bool {
        let zone = model.dropZone(at: info.location)
        model.dropHover = nil
        return DroppedFiles.load(from: info.itemProviders(for: [.fileURL])) { [model] urls in model.handleDrop(urls, on: zone) }
    }
}

struct FileDragHandle: NSViewRepresentable {
    let urls: [URL]
    let label: String
    let onBegin: () -> Void

    init(url: URL, onBegin: @escaping () -> Void) {
        self.init(urls: [url], label: "Drag into Ableton or any DAW", onBegin: onBegin)
    }

    init(urls: [URL], label: String, onBegin: @escaping () -> Void) {
        self.urls = urls; self.label = label; self.onBegin = onBegin
    }

    func makeNSView(context: Context) -> DragHandleNSView {
        let v = DragHandleNSView()
        v.configure(urls: urls, label: label, onBegin: onBegin)
        return v
    }

    func updateNSView(_ view: DragHandleNSView, context: Context) {
        view.configure(urls: urls, label: label, onBegin: onBegin)
    }
}

final class DragHandleNSView: NSView, NSDraggingSource {
    private var urls: [URL] = []
    private var label = ""
    private var onBegin: () -> Void = {}
    private var mouseDownPoint: NSPoint?

    func configure(urls: [URL], label: String, onBegin: @escaping () -> Void) {
        self.urls = urls; self.label = label; self.onBegin = onBegin
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
        let text = label as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                    .foregroundColor: NSColor.labelColor]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !urls.isEmpty,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        onBegin()
        let p = convert(event.locationInWindow, from: nil)
        let items = urls.prefix(8).enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(index) * 4
            item.setDraggingFrame(NSRect(x: p.x - 16 + offset, y: p.y - 16 - offset, width: 32, height: 32),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        // Files past the eighth ride along without extra drag images.
        let rest = urls.dropFirst(8).map { NSDraggingItem(pasteboardWriter: $0 as NSURL) }
        rest.forEach { $0.setDraggingFrame(NSRect(x: p.x, y: p.y, width: 1, height: 1), contents: nil) }
        beginDraggingSession(with: items + rest, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
