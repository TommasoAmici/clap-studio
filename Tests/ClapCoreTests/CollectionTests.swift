import Foundation
import Testing
@testable import ClapCore

@Suite struct CollectionTests {
    private func makeLibrary() throws -> (LibraryStore, [Int64]) {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: ["a.wav", "b.wav", "c.wav"].map { ScannedFile(relPath: $0, size: 1, mtime: 1) }) { _ in nil }
        return (store, store.loadSamples().map(\.id))
    }

    @Test func favoritesPersist() throws {
        let (store, ids) = try makeLibrary()
        try store.setFavorite([ids[0], ids[2]], true)
        #expect(store.loadSamples().filter(\.favorite).map(\.id) == [ids[0], ids[2]])
        try store.setFavorite([ids[0]], false)
        #expect(store.loadSamples().filter(\.favorite).map(\.id) == [ids[2]])
    }

    @Test func collectionLifecycle() throws {
        let (store, ids) = try makeLibrary()
        let drums = try store.createCollection(name: "  Drums ")
        _ = try store.createCollection(name: "Atmos")
        #expect(store.collections().map(\.name) == ["Atmos", "Drums"], "sorted by name, trimmed")

        let t = Date()
        try store.addToCollection(id: drums.id, sampleIDs: [ids[2], ids[0]], at: t)
        try store.addToCollection(id: drums.id, sampleIDs: [ids[0], ids[1]], at: t.addingTimeInterval(1))   // ids[0] twice
        #expect(store.collectionMembers(id: drums.id) == [ids[2], ids[0], ids[1]])
        #expect(store.collections().first { $0.id == drums.id }?.count == 3)

        try store.removeFromCollection(id: drums.id, sampleIDs: [ids[0]])
        #expect(store.collectionMembers(id: drums.id) == [ids[2], ids[1]])
        try store.renameCollection(id: drums.id, to: "Kits")
        try store.renameCollection(id: drums.id, to: "   ")
        #expect(store.collections().contains { $0.name == "Kits" })
        try store.deleteCollection(id: drums.id)
        #expect(store.collectionMembers(id: drums.id).isEmpty)
        #expect(store.collections().count == 1)
    }

    @Test func removingAFolderDropsItsSamplesFromCollections() throws {
        let (store, ids) = try makeLibrary()
        let c = try store.createCollection(name: "x")
        try store.addToCollection(id: c.id, sampleIDs: ids)
        try store.removeRoot(id: try #require(store.roots().first?.id))
        #expect(store.collectionMembers(id: c.id).isEmpty)
    }

    @Test func exportNeverOverwrites() throws {
        let src = TestSupport.tempDir(), dest = TestSupport.tempDir().appendingPathComponent("out")
        let one = src.appendingPathComponent("kick.wav"), two = src.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)
        let other = two.appendingPathComponent("kick.wav")
        try Data("one".utf8).write(to: one); try Data("two".utf8).write(to: other)

        let first = SampleExporter.copy([one, other], to: dest)
        #expect(first.copied.map(\.lastPathComponent) == ["kick.wav", "kick 2.wav"])
        let again = SampleExporter.copy([one], to: dest)
        #expect(again.copied.map(\.lastPathComponent) == ["kick 3.wav"])
        #expect(try Data(contentsOf: dest.appendingPathComponent("kick 2.wav")) == Data("two".utf8))
        let missing = SampleExporter.copy([src.appendingPathComponent("nope.wav")], to: dest)
        #expect(missing.copied.isEmpty && missing.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: one.path), "originals stay")
    }
}
