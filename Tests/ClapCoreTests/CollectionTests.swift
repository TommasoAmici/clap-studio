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

@Suite struct TagTests {
    @Test func tagsAreCaseInsensitiveSortedAndCleaned() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: ["a.wav", "b.wav"].map { ScannedFile(relPath: $0, size: 1, mtime: 1) }) { _ in nil }
        let ids = store.loadSamples().map(\.id)
        try store.addTag("  Dusty, vinyl ", to: ids)
        try store.addTag("dustyvinyl", to: [ids[0]])
        try store.addTag("Dustyvinyl", to: [ids[0]])      // same tag, different case: ignored
        try store.addTag("   ", to: ids)
        #expect(LibraryStore.cleanTag(" a,b\n") == "ab")
        #expect(LibraryStore.cleanTag(String(repeating: "x", count: 80)).count == 40)
        let first = try #require(store.loadSamples().first { $0.id == ids[0] })
        #expect(first.tags == ["Dusty vinyl", "dustyvinyl"])
        #expect(store.loadSamples().first { $0.id == ids[1] }?.tags == ["Dusty vinyl"])
        try store.removeTag("Dusty vinyl", from: [ids[1]])
        #expect(store.loadSamples().first { $0.id == ids[1] }?.tags == [])
    }
}

@Suite struct ExportNamingTests {
    private func sample(name: String = "Hit 01", category: String? = "Kick", bpm: Double? = nil, key: String? = nil, tags: [String] = []) -> SampleRecord {
        var s = SampleRecord(id: 1, rootID: 1, rootPath: "/", relPath: "Drums/\(name).wav", name: name, ext: "wav", duration: 1,
                             sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        s.category = category; s.bpm = bpm; s.keyName = key; s.tags = tags
        return s
    }

    @Test func templatesFillTokensAndDropEmptyOnes() {
        let loop = sample(name: "Loop", category: "Drum Loop", bpm: 127.6, key: "A minor")
        #expect(ExportNaming.fileName(template: "{category} - {name} - {bpm} - {key}", for: loop, position: 1, of: 3)
                == "Drum Loop - Loop - 128 - A minor.wav")
        let shot = sample()
        #expect(ExportNaming.fileName(template: "{category} - {name} - {bpm} - {key}", for: shot, position: 1, of: 3) == "Kick - Hit 01.wav",
                "no BPM or key: no dangling dashes")
        #expect(ExportNaming.fileName(template: "{n}_{name}", for: shot, position: 7, of: 120) == "007_Hit 01.wav")
        #expect(ExportNaming.fileName(template: "", for: shot, position: 1, of: 1) == "Hit 01.wav")
        #expect(ExportNaming.fileName(template: "{folder} {tags}", for: sample(tags: ["dusty", "vinyl"]), position: 1, of: 1) == "Drums dusty vinyl.wav")
    }

    @Test func unsafeCharactersAreRemoved() {
        let s = sample(name: "a/b:c")
        #expect(ExportNaming.fileName(template: "{name}", for: s, position: 1, of: 1) == "a-b-c.wav")
        #expect(ExportNaming.fileName(template: "../{name}", for: s, position: 1, of: 1) == "a-b-c.wav", "no path traversal")
        #expect(ExportNaming.fileName(template: "{bpm}", for: sample(category: nil), position: 1, of: 1) == "Hit 01.wav", "empty result falls back to the name")
    }
}
