import Foundation
import Testing
@testable import ClapCore

@Suite struct JoinedLinksTests {
    @Test func outputKeepsOrderedLinksEvenWhenTheSourceFolderIsRemoved() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sourceFolder = dir.appendingPathComponent("sources")
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("unindexed/Joined 1.wav"))
        let root = try store.addRoot(path: sourceFolder.path)
        try store.sync(rootID: root.id, scanned: [
            ScannedFile(relPath: "kick.wav", size: 1, mtime: 1),
            ScannedFile(relPath: "snare.wav", size: 1, mtime: 1),
        ]) { _ in nil }
        let samples = store.loadSamples().sorted { $0.name < $1.name }
        let sources = samples.map { JoinSource(url: $0.url, name: $0.name, sampleID: $0.id) }
        let pieces = [JoinedRegion(sourceIndex: 1, startFrame: 0, endFrame: 1_000),
                      JoinedRegion(sourceIndex: 0, sourceStartFrame: 200, startFrame: 1_100, endFrame: 1_500),
                      JoinedRegion(sourceIndex: 1, startFrame: 1_600, endFrame: 2_000)]
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: pieces)], sources: sources)
        let reopened = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let links = reopened.joinedParts(for: output)
        #expect(links.map(\.sourceID) == [samples[1].id, samples[0].id, samples[1].id],
                "Links retain the order and repeats actually written to this file.")
        #expect(links.map(\.sourceStartFrame) == [0, 200, 0], "A continuation keeps its original offset.")
        #expect(reopened.isJoinedFile(at: output), "Links survive restart even before the output folder is indexed.")
        try reopened.removeRoot(id: root.id)
        let missing = reopened.joinedParts(for: output)
        #expect(missing.map(\.sourceID) == [nil, nil, nil], "Removing source folders cannot link to reused IDs.")
        #expect(missing.map(\.name) == ["snare", "kick", "snare"], "Missing sources remain identifiable by name.")
    }
    @Test func removedSourceCannotLinkToAReusedID() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try store.addRoot(path: dir.appendingPathComponent("first").path)
        try store.sync(rootID: first.id, scanned: [ScannedFile(relPath: "sound.wav", size: 1, mtime: 1)]) { _ in nil }
        let original = try #require(store.loadSamples().first)
        let source = JoinSource(url: original.url, name: original.name, sampleID: original.id)
        try store.removeRoot(id: first.id)
        let second = try store.addRoot(path: dir.appendingPathComponent("second").path)
        try store.sync(rootID: second.id, scanned: [ScannedFile(relPath: "other.wav", size: 1, mtime: 1)]) { _ in nil }
        #expect(store.loadSamples().first?.id == original.id, "SQLite can reuse the removed sample's ID.")
        let output = TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("out.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])], sources: [source])
        #expect(store.joinedParts(for: output).first?.sourceID == nil,
                "The new file must not be mistaken for the original source.")
    }

}
