import ClapCore
import Foundation

/// Collections, and the sub-collections inside them (one level only). Every edit is one undo step.
extension AppModel {
    /// The sidebar's collections, each with its sub-collections.
    var collectionTree: [CollectionNode] { CollectionNode.tree(collections) }

    func collection(_ id: Int64) -> CollectionRecord? { collections.first { $0.id == id } }

    /// Whether picking the collection `id` shows samples held by `changed` (itself, or a sub-collection of it).
    private func selectionShows(_ changed: Int64) -> Bool {
        guard let selected = collectionSelection else { return false }
        return selected == changed || collection(changed)?.parentID == selected
    }

    func reloadCollections() {
        guard let store else { return }
        collections = store.collections()
        if let id = collectionSelection, !collections.contains(where: { $0.id == id }) { collectionSelection = nil }
        collectionMembers = collectionSelection.map { Set(store.collectionTreeMembers(id: $0)) } ?? []
    }

    /// Makes a collection, or a sub-collection when `parent` is given, holding `ids`. Undo removes it again.
    func createCollection(named name: String, with ids: [Int64] = [], parent: Int64? = nil) {
        guard let store else { return }
        var currentID: Int64
        let backup: CollectionBackup
        do {
            let collection = try store.createCollection(name: name, parentID: parent)
            try store.addToCollection(id: collection.id, sampleIDs: ids)
            currentID = collection.id
            guard let made = store.collectionBackup(id: collection.id) else { return }
            backup = made
        } catch { errorMessage = "Could not create the collection: \(error.localizedDescription)"; return }
        reloadCollections()
        record(LibraryEdit(name: parent == nil ? "New collection \(backup.name)" : "New sub-collection \(backup.name)",
                           undo: { [unowned self] in try? store.deleteCollection(id: currentID); reloadCollections(); refilter() },
                           redo: { [unowned self] in
                               if let restored = try? store.restoreCollection(backup) { currentID = restored.id }
                               reloadCollections(); refilter()
                           }))
    }

    func add(_ ids: [Int64], toCollection id: Int64) {
        guard let store else { return }
        let existing = Set(store.collectionMembers(id: id))
        let new = ids.filter { !existing.contains($0) }
        guard !new.isEmpty else { return }
        let name = collection(id)?.name ?? "collection"
        record(LibraryEdit(name: "Add \(samplesPhrase(new.count)) to \(name)",
                           undo: { [unowned self] in removeMembers(new, from: [id]) },
                           redo: { [unowned self] in addMembers(new, to: id) }))
        addMembers(new, to: id)
    }

    private func addMembers(_ ids: [Int64], to id: Int64) {
        guard let store else { return }
        do { try store.addToCollection(id: id, sampleIDs: ids) } catch { errorMessage = "Could not update the collection: \(error)"; return }
        reloadCollections()
        if selectionShows(id) { refilter() }
    }

    /// Takes samples out of a collection. Picking a collection shows its sub-collections' samples too, so removing from it
    /// takes them out of those as well; the collection list shows what was removed.
    func remove(_ ids: [Int64], fromCollection id: Int64) {
        guard let store else { return }
        let from = [id] + store.subCollectionIDs(of: id)
        var removals: [(collection: Int64, samples: [Int64])] = []
        for collection in from {
            let existing = Set(store.collectionMembers(id: collection))
            let present = ids.filter { existing.contains($0) }
            if !present.isEmpty { removals.append((collection, present)) }
        }
        guard !removals.isEmpty else { return }
        let count = Set(removals.flatMap(\.samples)).count
        record(LibraryEdit(name: "Remove \(samplesPhrase(count)) from \(collection(id)?.name ?? "collection")",
                           undo: { [unowned self] in for removal in removals { addMembers(removal.samples, to: removal.collection) } },
                           redo: { [unowned self] in for removal in removals { removeMembers(removal.samples, from: [removal.collection]) } }))
        for removal in removals { removeMembers(removal.samples, from: [removal.collection]) }
    }

    private func removeMembers(_ ids: [Int64], from collectionIDs: [Int64]) {
        guard let store else { return }
        for id in collectionIDs {
            do { try store.removeFromCollection(id: id, sampleIDs: ids) } catch { errorMessage = "Could not update the collection: \(error)"; return }
        }
        reloadCollections()
        if collectionIDs.contains(where: selectionShows) { refilter() }
    }

    func rename(collection id: Int64, to name: String) {
        guard let store, let old = collection(id)?.name else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != old else { return }
        do { try store.renameCollection(id: id, to: clean) } catch { errorMessage = "Could not rename the collection: \(error)"; return }
        reloadCollections()
        record(LibraryEdit(name: "Rename collection \(old)",
                           undo: { [unowned self] in try? store.renameCollection(id: id, to: old); reloadCollections() },
                           redo: { [unowned self] in try? store.renameCollection(id: id, to: clean); reloadCollections() }))
    }

    /// A collection with sub-collections asks before it is deleted, because they go with it.
    func subCollectionCount(of id: Int64) -> Int { collections.filter { $0.parentID == id }.count }

    /// Deletes a collection and its sub-collections. Samples and their files stay where they are.
    func delete(collection id: Int64) {
        guard let store, let backup = store.collectionBackup(id: id) else { return }
        var currentID = id
        do { try store.deleteCollection(id: id) } catch { errorMessage = "Could not delete the collection: \(error)"; return }
        reloadCollections()
        refilter()
        record(LibraryEdit(name: "Delete collection \(backup.name)",
                           undo: { [unowned self] in
                               if let restored = try? store.restoreCollection(backup) { currentID = restored.id }
                               reloadCollections(); refilter()
                           },
                           redo: { [unowned self] in try? store.deleteCollection(id: currentID); reloadCollections(); refilter() }))
    }

    /// Whether `id` can go inside another collection: it is not one that has sub-collections.
    func canNest(collection id: Int64) -> Bool { subCollectionCount(of: id) == 0 }

    /// Puts a collection inside another, or back at the top level with nil.
    func move(collection id: Int64, into parent: Int64?) {
        guard let store, let current = collection(id), current.parentID != parent else { return }
        let old = current.parentID
        do { try store.setParent(of: id, to: parent) } catch { errorMessage = error.localizedDescription; return }
        reloadCollections()
        refilter()
        record(LibraryEdit(name: "Move collection \(current.name)",
                           undo: { [unowned self] in try? store.setParent(of: id, to: old); reloadCollections(); refilter() },
                           redo: { [unowned self] in try? store.setParent(of: id, to: parent); reloadCollections(); refilter() }))
    }
}
