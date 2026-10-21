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
    /// Accepts the drop and delivers whatever file URLs could be read from it (possibly none: a drag that started
    /// in this app can then be recognised from `AppModel.recentDrags`).
    static func load(from providers: [NSItemProvider], perform: @escaping @MainActor ([URL]) -> Void) -> Bool {
        guard !providers.isEmpty else { return false }
        let fileURL = UTType.fileURL.identifier
        let group = DispatchGroup()
        let lock = NSLock()
        var found: [URL] = []
        func add(_ url: URL?) { if let url { lock.lock(); found.append(url); lock.unlock() } }
        for provider in providers {
            group.enter()
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    add(url); group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(fileURL) {
                provider.loadItem(forTypeIdentifier: fileURL, options: nil) { item, _ in
                    if let url = item as? URL { add(url) }
                    else if let data = item as? Data { add(URL(dataRepresentation: data, relativeTo: nil)) }
                    group.leave()
                }
            } else {
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
    /// Accepts file drags (from the library list, the kit builder, or Finder) and hands over their URLs.
    /// Highlights through `isTargeted` while a drag is over the view.
    func fileDrop(isTargeted: Binding<Bool>? = nil, perform: @escaping @MainActor ([URL]) -> Void) -> some View {
        onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            DroppedFiles.load(from: providers) { urls in if !urls.isEmpty { perform(urls) } }
        }
    }
}

// MARK: one window-wide drop target

/// Places inside the window that take dropped files. Nested drop targets are unreliable on macOS, so the window has
/// a single one and finds the place under the pointer from these frames.
enum DropZone: Hashable {
    case drumTrack(Int)         // a track row: dropping here swaps its sound
    case drums                  // the whole drawer
    case melody                 // the melody drawer: dropped samples become tracks
    case melodyTrack(Int)       // a track's tab in the melody drawer: dropping here swaps its sound
    case drumInsert(Int)        // not a frame: the gap before this track (or after the last), worked out from the pointer
}

struct DropZoneFrames: PreferenceKey {
    static let defaultValue: [DropZone: CGRect] = [:]
    static func reduce(value: inout [DropZone: CGRect], nextValue: () -> [DropZone: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where the pointer is, in the same space the zone frames are measured in (the window's content, top left origin).
@MainActor func pointerInWindowContent() -> CGPoint? {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let content = window.contentView else { return nil }
    let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
    let local = content.convert(inWindow, from: nil)
    return CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
}

extension View {
    func dropZone(_ zone: DropZone) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: DropZoneFrames.self, value: [zone: proxy.frame(in: .global)])
        })
    }
}

struct WindowDropDelegate: DropDelegate {
    let model: AppModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    private func zone(for info: DropInfo) -> DropZone? {
        let pointer = MainActor.assumeIsolated { pointerInWindowContent() }
        return pointer.flatMap { model.dropZone(at: $0) }
    }

    func dropEntered(info: DropInfo) {
        model.dropHover = zone(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let zone = zone(for: info)
        if zone != model.dropHover { model.dropHover = zone }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { model.dropHover = nil }

    func performDrop(info: DropInfo) -> Bool {
        let zone = zone(for: info)
        model.dropHover = nil
        return DroppedFiles.load(from: info.itemProviders(for: [.fileURL])) { [model] urls in
            model.handleDrop(urls, on: zone)
        }
    }
}
