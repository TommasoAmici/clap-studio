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

    // MARK: collections

    func reloadCollections() {
        guard let store else { return }
        collections = store.collections()
        if let id = collectionSelection, !collections.contains(where: { $0.id == id }) { collectionSelection = nil }
        collectionMembers = collectionSelection.map { Set(store.collectionMembers(id: $0)) } ?? []
    }

    func createCollection(named name: String, with ids: [Int64] = []) {
        guard let store else { return }
        do {
            let collection = try store.createCollection(name: name)
            try store.addToCollection(id: collection.id, sampleIDs: ids)
        } catch { errorMessage = "Could not create the collection: \(error)"; return }
        reloadCollections()
    }

    func add(_ ids: [Int64], toCollection id: Int64) {
        guard let store else { return }
        let existing = Set(store.collectionMembers(id: id))
        let new = ids.filter { !existing.contains($0) }
        guard !new.isEmpty else { return }
        let name = collections.first { $0.id == id }?.name ?? "collection"
        record(LibraryEdit(name: "Add \(samplesPhrase(new.count)) to \(name)",
                           undo: { [unowned self] in removeMembers(new, from: id) },
                           redo: { [unowned self] in addMembers(new, to: id) }))
        addMembers(new, to: id)
    }

    private func addMembers(_ ids: [Int64], to id: Int64) {
        guard let store else { return }
        do { try store.addToCollection(id: id, sampleIDs: ids) } catch { errorMessage = "Could not update the collection: \(error)"; return }
        reloadCollections()
        if collectionSelection == id { refilter() }
    }

    func remove(_ ids: [Int64], fromCollection id: Int64) {
        guard let store else { return }
        let existing = Set(store.collectionMembers(id: id))
        let present = ids.filter { existing.contains($0) }
        guard !present.isEmpty else { return }
        let name = collections.first { $0.id == id }?.name ?? "collection"
        record(LibraryEdit(name: "Remove \(samplesPhrase(present.count)) from \(name)",
                           undo: { [unowned self] in addMembers(present, to: id) },
                           redo: { [unowned self] in removeMembers(present, from: id) }))
        removeMembers(present, from: id)
    }

    private func removeMembers(_ ids: [Int64], from id: Int64) {
        guard let store else { return }
        do { try store.removeFromCollection(id: id, sampleIDs: ids) } catch { errorMessage = "Could not update the collection: \(error)"; return }
        reloadCollections()
        if collectionSelection == id { refilter() }
    }

    func rename(collection id: Int64, to name: String) {
        try? store?.renameCollection(id: id, to: name)
        reloadCollections()
    }

    func delete(collection id: Int64) {
        guard let store, let collection = collections.first(where: { $0.id == id }) else { return }
        let members = store.collectionMembers(id: id)
        var currentID = id
        try? store.deleteCollection(id: id)
        reloadCollections()
        record(LibraryEdit(name: "Delete collection \(collection.name)",
                           undo: { [unowned self] in
                               if let restored = try? store.createCollection(name: collection.name) {
                                   currentID = restored.id
                                   try? store.addToCollection(id: restored.id, sampleIDs: members)
                                   reloadCollections()
                               }
                           },
                           redo: { [unowned self] in
                               try? store.deleteCollection(id: currentID)
                               reloadCollections()
                           }))
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
