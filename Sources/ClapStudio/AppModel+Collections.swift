import AppKit
import ClapCore
import Foundation

/// Favorites, collections and the tray (a scratch list to drag out or copy several samples at once).
extension AppModel {
    // MARK: sidebar selection

    /// One thing is selected in the sidebar at a time: a folder, a collection, a category or a smart filter.
    var sidebarTag: String {
        if let folder = folderSelection { return folder }
        if let id = collectionSelection { return "col.\(id)" }
        if let category = descriptorFilter.category { return "cat.\(category)" }
        return "smart.\(smartFilter.rawValue)"
    }

    func selectSidebar(_ tag: String) {
        folderSelection = nil
        collectionSelection = nil
        descriptorFilter.category = nil
        smartFilter = .all
        if tag.hasPrefix("col.") { collectionSelection = Int64(tag.dropFirst(4)) }
        else if tag.hasPrefix("cat.") { descriptorFilter.category = String(tag.dropFirst(4)) }
        else if tag.hasPrefix("smart.") { smartFilter = SmartFilter(rawValue: String(tag.dropFirst(6))) ?? .all }
        else { folderSelection = tag }
    }

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

    // MARK: tray

    var traySamples: [SampleRecord] { tray.compactMap { sampleByID[$0] } }

    func addToTray(_ ids: [Int64]) {
        for id in ids where !tray.contains(id) { tray.append(id) }
    }

    func removeFromTray(_ id: Int64) { tray.removeAll { $0 == id } }

    func clearTray() { tray = [] }

    /// A drag of the whole tray counts as one grab per sample.
    func registerTrayGrab() { for id in tray { registerGrab(id) } }

    /// Copies the tray's files into a folder the user picks; the originals stay where they are.
    func exportTray() {
        let samples = traySamples
        guard !samples.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Copy Here"
        panel.message = "Copy \(samples.count) samples to this folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let urls = samples.map(\.url)
        Task {
            let report = await Task.detached { SampleExporter.copy(urls, to: folder) }.value
            if let first = report.copied.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
            if !report.failures.isEmpty {
                errorMessage = "Copied \(report.copied.count) of \(samples.count). Could not copy: "
                    + report.failures.prefix(3).map { $0.source.lastPathComponent }.joined(separator: ", ")
            }
        }
    }
}
