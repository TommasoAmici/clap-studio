import Foundation
import Testing
@testable import ClapCore

@Suite struct StoreTests {
    private func scanned(_ rel: String, size: Int64 = 100, mtime: Double = 1) -> ScannedFile {
        ScannedFile(relPath: rel, size: size, mtime: mtime)
    }

    @Test func syncAddsThenSkipsUnchanged() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        let files = [scanned("kick.wav"), scanned("hats/hat.wav")]
        let first = try store.sync(rootID: root.id, scanned: files) { _ in nil }
        #expect(first.added == 2)
        let second = try store.sync(rootID: root.id, scanned: files) { _ in nil }
        #expect(second.added == 0 && second.unchanged == 2)
    }

    @Test func embeddingsAndUsageSurviveReopen() throws {
        let dir = TestSupport.tempDir()
        let path = dir.appendingPathComponent("lib.sqlite").path
        var id: Int64 = 0
        do {
            let store = try LibraryStore(path: path)
            let root = try store.addRoot(path: "/tmp/x")
            try store.sync(rootID: root.id, scanned: [scanned("a.wav")]) { _ in "fp" }
            id = store.pendingJobs(limit: 10)[0].id
            try store.save(results: [.success(id: id, duration: 1, sampleRate: 44100, channels: 2,
                                              embedding: [0.5, -0.25], fingerprint: "fp", modelVersion: "m1")])
            try store.recordGrab(sampleID: id)
            try store.recordGrab(sampleID: id)
        }
        let reopened = try LibraryStore(path: path)
        #expect(reopened.pendingCount() == 0)
        let samples = reopened.loadSamples()
        #expect(samples.count == 1)
        #expect(samples[0].status == .ok && samples[0].useCount == 2 && samples[0].duration == 1)
        let r = try reopened.addRoot(path: "/tmp/x")
        let again = try reopened.sync(rootID: r.id, scanned: [scanned("a.wav")]) { _ in nil }
        #expect(again.unchanged == 1 && reopened.pendingCount() == 0)
    }

    @Test func movedFileKeepsEmbeddingAndUsage() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [scanned("old/a.wav")]) { _ in "fp-a" }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: 1, sampleRate: 44100, channels: 1,
                                          embedding: [1], fingerprint: "fp-a", modelVersion: "m1")])
        try store.recordGrab(sampleID: id)
        let r = try store.sync(rootID: root.id, scanned: [scanned("new/b.wav")]) { _ in "fp-a" }
        #expect(r.moved == 1 && r.added == 0)
        let s = store.loadSamples()
        #expect(s.count == 1 && s[0].id == id && s[0].relPath == "new/b.wav" && s[0].useCount == 1)
        #expect(store.pendingCount() == 0)
    }

    @Test func removedFileIsHiddenNotDeleted() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [scanned("a.wav")]) { _ in "fp" }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: 1, sampleRate: 1, channels: 1,
                                          embedding: [1], fingerprint: "fp", modelVersion: "m")])
        try store.recordGrab(sampleID: id)
        try store.sync(rootID: root.id, scanned: []) { _ in nil }
        #expect(store.loadSamples().isEmpty)
        try store.sync(rootID: root.id, scanned: [scanned("a.wav")]) { _ in nil }
        let back = store.loadSamples()
        #expect(back.count == 1 && back[0].useCount == 1 && back[0].status == .ok)
    }

    @Test func staleModelRequeues() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [scanned("a.wav")]) { _ in nil }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: 1, sampleRate: 1, channels: 1,
                                          embedding: [1], fingerprint: nil, modelVersion: "old")])
        #expect(try store.markStale(currentModelVersion: "old") == 0)
        #expect(try store.markStale(currentModelVersion: "new") == 1)
        #expect(store.pendingCount() == 1)
    }

    @Test func scannerFindsAudioOnlyAndIsReadOnly() throws {
        let dir = TestSupport.tempDir()
        TestSupport.write([1, 2, 3], to: dir.appendingPathComponent("a.wav"))
        TestSupport.write([1], to: dir.appendingPathComponent("sub/b.AIF"))
        TestSupport.write([1], to: dir.appendingPathComponent("notes.txt"))
        TestSupport.write([1], to: dir.appendingPathComponent(".hidden.wav"))
        let files = FolderScanner.scan(root: dir).map(\.relPath).sorted()
        #expect(files == ["a.wav", "sub/b.AIF"], "got \(files)")
        #expect(FileFingerprint.compute(url: dir.appendingPathComponent("a.wav")) != nil)
    }
}
