import Foundation
import Testing
@testable import ClapCore

@Suite struct NestedCollectionTests {
    private func makeLibrary() throws -> (LibraryStore, [Int64]) {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: ["a.wav", "b.wav", "c.wav", "d.wav"].map { ScannedFile(relPath: $0, size: 1, mtime: 1) }) { _ in nil }
        return (store, store.loadSamples().map(\.id))
    }

    @Test func aSubCollectionKnowsItsParent() throws {
        let (store, _) = try makeLibrary()
        let party = try store.createCollection(name: "Party #23")
        let opening = try store.createCollection(name: "Opening", parentID: party.id)
        let found = try #require(store.collections().first { $0.id == opening.id })
        #expect(found.parentID == party.id && found.name == "Opening")
        #expect(store.collections().first { $0.id == party.id }?.parentID == nil)
    }

    @Test func onlyOneLevelOfNestingIsAllowed() throws {
        let (store, _) = try makeLibrary()
        let party = try store.createCollection(name: "Party")
        let opening = try store.createCollection(name: "Opening", parentID: party.id)
        let other = try store.createCollection(name: "Other")
        #expect(throws: CollectionError.tooDeep) { try store.createCollection(name: "Deeper", parentID: opening.id) }
        #expect(throws: CollectionError.tooDeep) { try store.setParent(of: party.id, to: other.id) }
        #expect(throws: CollectionError.tooDeep) { try store.setParent(of: other.id, to: opening.id) }
        #expect(throws: CollectionError.tooDeep) { try store.setParent(of: other.id, to: other.id) }
        #expect(throws: CollectionError.missingParent) { try store.createCollection(name: "Lost", parentID: 9_999) }
        try store.setParent(of: opening.id, to: other.id)
        #expect(store.collections().first { $0.id == opening.id }?.parentID == other.id, "A sub-collection can move to another collection.")
        try store.setParent(of: opening.id, to: nil)
        #expect(store.collections().first { $0.id == opening.id }?.parentID == nil, "Or back to the top level.")
        try store.setParent(of: party.id, to: other.id)
        #expect(store.collections().first { $0.id == party.id }?.parentID == other.id, "Once it has no children a collection can become one.")
    }

    @Test func aParentShowsItsOwnSamplesAndThoseOfItsChildren() throws {
        let (store, ids) = try makeLibrary()
        let party = try store.createCollection(name: "Party")
        let opening = try store.createCollection(name: "Opening", parentID: party.id)
        let peak = try store.createCollection(name: "Peak", parentID: party.id)
        try store.addToCollection(id: party.id, sampleIDs: [ids[0], ids[1]])
        try store.addToCollection(id: opening.id, sampleIDs: [ids[1], ids[2]])
        try store.addToCollection(id: peak.id, sampleIDs: [ids[3]])
        #expect(Set(store.collectionTreeMembers(id: party.id)) == Set(ids), "Own samples and both children's, each once.")
        #expect(store.collectionTreeMembers(id: party.id).count == 4, "A sample in the parent and a child is not repeated.")
        #expect(store.collectionMembers(id: party.id) == [ids[0], ids[1]], "The parent's own samples stay separate for sending.")
        #expect(Set(store.collectionTreeMembers(id: opening.id)) == [ids[1], ids[2]])
        let records = store.collections()
        #expect(records.first { $0.id == party.id }?.count == 4, "The count is what selecting the collection shows.")
        #expect(records.first { $0.id == party.id }?.ownCount == 2)
        #expect(records.first { $0.id == opening.id }?.count == 2)
    }

    @Test func deletingAParentDeletesItsSubCollectionsButNoSamples() throws {
        let (store, ids) = try makeLibrary()
        let party = try store.createCollection(name: "Party")
        let opening = try store.createCollection(name: "Opening", parentID: party.id)
        let keep = try store.createCollection(name: "Keep")
        try store.addToCollection(id: opening.id, sampleIDs: ids)
        try store.addToCollection(id: keep.id, sampleIDs: [ids[0]])
        try store.deleteCollection(id: party.id)
        #expect(store.collections().map(\.name) == ["Keep"], "The parent and its sub-collection are both gone.")
        #expect(store.collectionMembers(id: opening.id).isEmpty, "Their memberships are removed too.")
        #expect(store.loadSamples().count == 4 && store.collectionMembers(id: keep.id) == [ids[0]], "Samples and other collections are untouched.")
    }

    @Test func deletingASubCollectionLeavesTheParent() throws {
        let (store, ids) = try makeLibrary()
        let party = try store.createCollection(name: "Party")
        let opening = try store.createCollection(name: "Opening", parentID: party.id)
        try store.addToCollection(id: party.id, sampleIDs: [ids[0]])
        try store.deleteCollection(id: opening.id)
        #expect(store.collections().map(\.name) == ["Party"] && store.collectionMembers(id: party.id) == [ids[0]])
    }

    @Test func aDeletedParentComesBackWithItsSubCollectionsAndSamples() throws {
        let (store, ids) = try makeLibrary()
        let party = try store.createCollection(name: "Party")
        let opening = try store.createCollection(name: "Opening", parentID: party.id)
        let peak = try store.createCollection(name: "Peak", parentID: party.id)
        try store.addToCollection(id: party.id, sampleIDs: [ids[0]])
        try store.addToCollection(id: opening.id, sampleIDs: [ids[1], ids[2]])
        try store.addToCollection(id: peak.id, sampleIDs: [ids[3]])
        let backup = try #require(store.collectionBackup(id: party.id))
        try store.deleteCollection(id: party.id)
        let restored = try store.restoreCollection(backup)
        let all = store.collections()
        #expect(all.map(\.name).sorted() == ["Opening", "Party", "Peak"])
        #expect(all.filter { $0.parentID == restored.id }.map(\.name).sorted() == ["Opening", "Peak"])
        #expect(Set(store.collectionTreeMembers(id: restored.id)) == Set(ids))
        let reopening = try #require(all.first { $0.name == "Opening" })
        #expect(store.collectionMembers(id: reopening.id) == [ids[1], ids[2]], "Each sub-collection keeps its own samples in order.")
    }

    @Test func theTreeListsSubCollectionsUnderTheirParentByName() throws {
        let (store, _) = try makeLibrary()
        let zed = try store.createCollection(name: "Zed")
        let party = try store.createCollection(name: "Party")
        _ = try store.createCollection(name: "Peak", parentID: party.id)
        _ = try store.createCollection(name: "Opening", parentID: party.id)
        let tree = CollectionNode.tree(store.collections())
        #expect(tree.map(\.record.name) == ["Party", "Zed"])
        #expect(tree[0].children?.map(\.record.name) == ["Opening", "Peak"])
        #expect(tree[1].children == nil, "A collection with no sub-collections shows no disclosure arrow.")
        #expect(CollectionNode.menuEntries(tree).map(\.title) == ["Party", "Party › Opening", "Party › Peak", "Zed"])
        _ = zed
    }

    @Test func anOlderLibraryGainsTheParentColumn() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try store.createCollection(name: "Old")
        try store.db.exec("DROP INDEX collections_parent")
        try store.db.exec("ALTER TABLE collections DROP COLUMN parent_id")
        try store.db.exec("PRAGMA user_version = 16")
        let migrated = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        #expect(migrated.collections().map(\.name) == ["Old"] && migrated.collections().first?.parentID == nil)
        let child = try migrated.createCollection(name: "New", parentID: old.id)
        #expect(migrated.collections().first { $0.id == child.id }?.parentID == old.id)
    }
}
