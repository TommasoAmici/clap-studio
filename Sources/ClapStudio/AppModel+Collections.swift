import AppKit
import ClapCore
import Foundation

/// Favorites, collections and copying samples to a folder.
extension AppModel {
    // MARK: sidebar selection

    /// One thing is selected in the sidebar at a time: a folder, a collection, a category, a mood or a smart filter.
    var sidebarTag: String {
        if let usb = usbSelection { return usb.tag }
        if let folder = folderSelection { return folder }
        if let id = collectionSelection { return "col.\(id)" }
        if let tag = tagFilter { return "tag.\(tag)" }
        if let category = descriptorFilter.category { return "cat.\(category)" }
        if descriptorFilter.moods.count == 1, let mood = descriptorFilter.moods.first { return "mood.\(mood)" }
        return "smart.\(smartFilter.rawValue)"
    }

    func selectSidebar(_ tag: String) {
        batchFilterChanges { applySidebarSelection(tag) }
    }

    private func applySidebarSelection(_ tag: String) {
        usbSelection = nil
        folderSelection = nil
        collectionSelection = nil
        tagFilter = nil
        descriptorFilter.category = nil
        descriptorFilter.moods = []
        smartFilter = .all
        if let usb = UsbSelection(tag: tag) { usbSelection = usb }
        else if tag.hasPrefix("tag.") { tagFilter = String(tag.dropFirst(4)) }
        else if tag.hasPrefix("col.") { collectionSelection = Int64(tag.dropFirst(4)) }
        else if tag.hasPrefix("cat.") { descriptorFilter.category = String(tag.dropFirst(4)) }
        else if tag.hasPrefix("mood.") { descriptorFilter.moods = [String(tag.dropFirst(5))] }
        else if tag.hasPrefix("smart.") { smartFilter = SmartFilter(rawValue: String(tag.dropFirst(6))) ?? .all }
        else { folderSelection = tag }
    }

    // MARK: shuffle

    /// The list is in plain sort order (not ranked by a search, a similarity query or usage), so shuffling means something.
    var canShuffle: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty && exampleQuery == nil
            && smartFilter != .mostUsed && smartFilter != .recentlyGrabbed
    }

    /// Puts the list in a new random order, so browsing does not always start with the same samples.
    func shuffleList() {
        guard canShuffle else { return }
        shuffleSeed = UInt64.random(in: 1...UInt64.max)
    }

    func endShuffle() { shuffleSeed = nil }

    // MARK: favorites

    func toggleFavorite(_ ids: [Int64]) {
        let anyNew = ids.contains { sampleByID[$0]?.favorite == false }
        let changed = ids.filter { sampleByID[$0]?.favorite == !anyNew }
        guard !changed.isEmpty else { return }
        record(LibraryEdit(name: anyNew ? "Favorite \(samplesPhrase(changed.count))" : "Unfavorite \(samplesPhrase(changed.count))",
                           undo: { [unowned self] in setFavorite(changed, !anyNew) },
                           redo: { [unowned self] in setFavorite(changed, anyNew) }))
        setFavorite(changed, anyNew)
    }

    private func setFavorite(_ ids: [Int64], _ favorite: Bool) {
        guard let store, !ids.isEmpty else { return }
        do { try store.setFavorite(ids, favorite) } catch { errorMessage = "Could not save favorites: \(error)"; return }
        for id in ids { mutate(id) { $0.favorite = favorite } }
        if smartFilter == .favorites { refilter() }
    }

    func collectionIDs(containing sampleID: Int64) -> Set<Int64> {
        guard let store else { return [] }
        return Set(collections.filter { store.collectionMembers(id: $0.id).contains(sampleID) }.map(\.id))
    }

    /// Copies the chosen samples into a folder the user picks (trimmed ones as trimmed WAV files); the originals stay where they are.
    func exportSelection(template: String, format: ExportFormat) {
        let samples = exportSamples
        guard !samples.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Copy Here"
        panel.message = "Copy \(samplesPhrase(samples.count)) to this folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let items = samples.enumerated().map { index, sample in
            TrimExporter.Item(source: sample.url, trim: activeTrim(for: sample),
                              fileName: ExportNaming.fileName(template: template, for: sample, position: index + 1, of: samples.count))
        }
        Task {
            let report = await Task.detached { TrimExporter.export(items, format: format, to: folder) }.value
            if let first = report.copied.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
            if !report.failures.isEmpty {
                errorMessage = "Copied \(report.copied.count) of \(samples.count). Could not copy: "
                    + report.failures.prefix(3).map { $0.source.lastPathComponent }.joined(separator: ", ")
            }
        }
    }
}
