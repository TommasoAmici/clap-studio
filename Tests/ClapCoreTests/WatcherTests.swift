import Foundation
import Testing
@testable import ClapCore

@Suite struct WatcherTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private func waitUntil(_ timeout: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if condition() { return true }; try? await Task.sleep(for: .milliseconds(100)) }
        return condition()
    }

    @Test func reportsNewAudioButIgnoresOtherFiles() async throws {
        let dir = TestSupport.tempDir()
        let real = URL(fileURLWithPath: realPathForTest(dir.path))
        let counter = Counter()
        let watcher = FolderWatcher(paths: [real.path], latency: 0.2) { counter.bump() }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(500))

        try Data("notes".utf8).write(to: real.appendingPathComponent("readme.txt"))
        try await Task.sleep(for: .seconds(1))
        #expect(counter.value == 0, "non-audio files are not interesting")

        try writeTestWav(real.appendingPathComponent("new.wav"), seconds: 0.1) { _ in 0.1 }
        #expect(await waitUntil(5) { counter.value > 0 }, "a new audio file is reported")
    }

    @Test func relevanceRules() {
        let file = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)
        let dir = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemCreated)
        let touchedDir = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemInodeMetaMod)
        #expect(FolderWatcher.isRelevant(paths: ["/a/kick.WAV"], flags: [file]))
        #expect(!FolderWatcher.isRelevant(paths: ["/a/notes.txt"], flags: [file]))
        #expect(FolderWatcher.isRelevant(paths: ["/a/New Folder"], flags: [dir]))
        #expect(!FolderWatcher.isRelevant(paths: ["/a"], flags: [touchedDir]), "a folder merely touched is not news")
    }

    private func realPathForTest(_ path: String) -> String { (path as NSString).resolvingSymlinksInPath }
}
