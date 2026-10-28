import Foundation
import Testing
@testable import ClapCore

@Suite struct JoinedKindTests {
    @Test func joinedFilesAreSeparateFromOtherSampleTypes() {
        var sound = SampleRecord(id: 1, rootID: 1, rootPath: "/tmp", relPath: "a.wav", name: "a", ext: "wav",
                                 duration: 45, sampleRate: 44_100, channels: 1, size: 1, mtime: 0,
                                 status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        sound.isJoined = true
        sound.isLoop = true
        var filter = DescriptorFilter()
        #expect(filter.matches(sound), "All still includes joined samples.")
        for kind in [DescriptorFilter.Kind.oneShot, .loop, .fieldRecording] {
            filter.kind = kind
            #expect(!filter.matches(sound), "A joined file does not masquerade as another sample type.")
        }
        filter.kind = .joined
        #expect(filter.matches(sound))
        sound.isJoined = false
        #expect(!filter.matches(sound), "The Joined filter excludes ordinary samples.")
    }

    @Test func indexedJoinedFilesStayJoinedWhenRenamed() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try store.addRoot(path: dir.path)
        let original = dir.appendingPathComponent("Joined.wav")
        let source = JoinSource(url: dir.appendingPathComponent("source.wav"))
        try store.recordJoinedOutputs([JoinedOutput(url: original, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])], sources: [source])
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "Joined.wav", size: 2, mtime: 1)]) { _ in "fingerprint" }
        #expect(store.loadSamples().first?.isJoined == true, "An indexed output is recognised as joined.")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "renamed.wav", size: 2, mtime: 1)]) { _ in "fingerprint" }
        let moved = try #require(store.loadSamples().first)
        #expect(moved.name == "renamed" && moved.isJoined, "A recognised rename carries its links with it.")
        #expect(store.joinedParts(for: moved.url).map(\.name) == ["source"])
    }
    @Test func noncanonicalRootStillRecognisesJoinedFiles() throws {
        let (store, dir) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try store.addRoot(path: dir.appendingPathComponent("sub/..", isDirectory: true).path + "/")
        let output = dir.appendingPathComponent("Joined.wav")
        try store.recordJoinedOutputs([JoinedOutput(url: output, regions: [JoinedRegion(sourceIndex: 0, startFrame: 0, endFrame: 1)])],
                                      sources: [JoinSource(url: dir.appendingPathComponent("source.wav"))])
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "Joined.wav", size: 2, mtime: 1)]) { _ in nil }
        #expect(store.loadSamples().first?.isJoined == true, "Trailing slashes and parent components do not hide joined files.")
    }

    @Test func classifyingPublishedFilesKeepsLaterLibraryEdits() {
        var sound = SampleRecord(id: 9, rootID: 2, rootPath: "/tmp", relPath: "Joined.wav", name: "Joined", ext: "wav",
                                 duration: 1, sampleRate: 44_100, channels: 1, size: 1, mtime: 0,
                                 status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        sound.favorite = true
        sound.tags = ["edited after export started"]
        var current = [sound]
        let changed = JoinedLibrary.markJoined(in: &current, pathsByRoot: [2: ["Joined.wav"]])
        #expect(changed == [9] && current[0].isJoined, "The newly joined file becomes available to the filter.")
        #expect(current[0].favorite && current[0].tags == ["edited after export started"],
                "Classifying never replaces edits made while the file was being exported.")
        #expect(JoinedLibrary.markJoined(in: &current, pathsByRoot: [2: ["Joined.wav"]]).isEmpty,
                "Refreshing the same output does not change it again.")
    }

}
