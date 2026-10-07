import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import ClapCore

/// Hand-assembles a PCM16 mono WAV, optionally with cue chunks and an odd-sized extra chunk.
func makeWav(frames: Int = 4410, cues: [FileCue] = [], withOddInfoChunk: Bool = false, cueFirst: Bool = false) -> Data {
    func chunk(_ id: String, _ payload: Data) -> Data {
        var d = Data(id.utf8); d.appendLE32(UInt32(payload.count)); d.append(payload)
        if payload.count & 1 == 1 { d.append(0) }
        return d
    }
    var fmt = Data()
    fmt.append(contentsOf: [1, 0, 1, 0]); fmt.appendLE32(44100); fmt.appendLE32(88200); fmt.append(contentsOf: [2, 0, 16, 0])
    var pcm = Data()
    for i in 0..<frames {
        let v = Int16(8000 * sin(2 * .pi * 440 * Double(i) / 44100))
        pcm.append(contentsOf: [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)])
    }
    var body = Data("WAVE".utf8)
    body.append(chunk("fmt ", fmt))
    var cueData = Data()
    if !cues.isEmpty {
        var p = Data(); p.appendLE32(UInt32(cues.count))
        for (i, c) in cues.enumerated() {
            p.appendLE32(UInt32(i + 1)); p.appendLE32(UInt32(c.frame)); p.append(contentsOf: Array("data".utf8))
            p.appendLE32(0); p.appendLE32(0); p.appendLE32(UInt32(c.frame))
        }
        cueData.append(chunk("cue ", p))
        var adtl = Data("adtl".utf8)
        for (i, c) in cues.enumerated() where !c.label.isEmpty {
            var l = Data(); l.appendLE32(UInt32(i + 1)); l.append(Data(c.label.utf8)); l.append(0)
            adtl.append(chunk("labl", l))
        }
        cueData.append(chunk("LIST", adtl))
    }
    if cueFirst { body.append(cueData) }
    if withOddInfoChunk {
        var info = Data("INFO".utf8); info.append(chunk("ISFT", Data("abc".utf8)))   // odd-sized
        body.append(chunk("LIST", info))
    }
    body.append(chunk("data", pcm))
    if !cueFirst { body.append(cueData) }
    var out = Data("RIFF".utf8); out.appendLE32(UInt32(body.count)); out.append(body)
    return out
}

func didThrow(_ body: () throws -> Any?) -> Bool {
    do { _ = try body(); return false } catch { return true }
}

@Suite struct CueTests {
    @Test func readsCuesAndLabelsWithOddPadding() throws {
        let dir = TestSupport.tempDir()
        let cues = [FileCue(frame: 1000, label: "Hit"), FileCue(frame: 200, label: ""), FileCue(frame: 3000, label: "Tail!")]
        let url = dir.appendingPathComponent("a.wav")
        try makeWav(cues: cues, withOddInfoChunk: true).write(to: url)
        let read = CueFileReader.read(url: url)
        #expect(read == [FileCue(frame: 200), FileCue(frame: 1000, label: "Hit"), FileCue(frame: 3000, label: "Tail!")])
    }

    @Test func malformedFilesDoNotCrashOrOverread() throws {
        let dir = TestSupport.tempDir()
        var data = makeWav(cues: [FileCue(frame: 5, label: "x")])
        data.removeLast(9)                                  // truncate inside the LIST chunk
        let truncated = dir.appendingPathComponent("t.wav"); try data.write(to: truncated)
        _ = CueFileReader.read(url: truncated)

        var hostile = makeWav(cues: [FileCue(frame: 5)])
        let cueOffset = hostile.range(of: Data("cue ".utf8))!.lowerBound
        hostile.replaceSubrange((cueOffset + 8)..<(cueOffset + 12), with: [0xFF, 0xFF, 0xFF, 0x7F])   // absurd cue count
        let h = dir.appendingPathComponent("h.wav"); try hostile.write(to: h)
        #expect(CueFileReader.read(url: h).count <= 1)

        let garbage = dir.appendingPathComponent("g.wav"); try Data(repeating: 0xAB, count: 64).write(to: garbage)
        #expect(CueFileReader.read(url: garbage).isEmpty)
        #expect(CueFileReader.read(url: dir.appendingPathComponent("missing.wav")).isEmpty)
    }

    @Test func readsAiffMarkers() throws {
        func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        var mark = Data([0, 2])
        mark.append(contentsOf: [0, 1] + be32(100) + [3] + Array("abc".utf8))          // 1+3 -> padded
        mark.append(contentsOf: [0, 2] + be32(250) + [0, 0])                            // empty name, padded
        var form = Data("AIFF".utf8)
        form.append(contentsOf: Array("MARK".utf8) + be32(UInt32(mark.count))); form.append(mark)
        var file = Data("FORM".utf8); file.append(contentsOf: be32(UInt32(form.count))); file.append(form)
        let url = TestSupport.tempDir().appendingPathComponent("m.aif"); try file.write(to: url)
        #expect(CueFileReader.read(url: url) == [FileCue(frame: 100, label: "abc"), FileCue(frame: 250)])
    }

    @Test func writerRoundTripKeepsAudioAndOtherChunks() throws {
        let dir = TestSupport.tempDir()
        let url = dir.appendingPathComponent("w.wav")
        let original = makeWav(cues: [FileCue(frame: 10, label: "old")], withOddInfoChunk: true, cueFirst: true)
        try original.write(to: url)
        let new = [FileCue(frame: 500, label: "Snare"), FileCue(frame: 20)]
        let backup = try WavCueWriter.write(cues: new, to: url, keepBackup: true)

        #expect(CueFileReader.read(url: url) == [FileCue(frame: 20), FileCue(frame: 500, label: "Snare")])
        let backupData = try backup.map { try Data(contentsOf: $0) }
        #expect(backupData == original)
        let after = try Data(contentsOf: url)
        func digest(_ d: Data, _ id: String) -> Data? {
            WavChunks.parse(d).first { $0.id == id }.map { d[$0.dataStart..<($0.dataStart + $0.size)] }
        }
        #expect(digest(after, "data") == digest(original, "data"))
        #expect(digest(after, "fmt ") == digest(original, "fmt "))
        let info = WavChunks.parse(after).filter { $0.id == "LIST" }.map { String(decoding: after[$0.dataStart..<($0.dataStart + 4)], as: UTF8.self) }
        #expect(info.contains("INFO") && info.contains("adtl"))
        let decoded = try AVAudioFile(forReading: url)                  // still a valid audio file
        #expect(decoded.length == 4410)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test func writerRefusesUnsupportedAndLeavesFileUntouched() throws {
        let dir = TestSupport.tempDir()
        let aiff = dir.appendingPathComponent("x.aif"); try Data(count: 40).write(to: aiff)
        let threw = didThrow { try WavCueWriter.write(cues: [], to: aiff, keepBackup: false) }
        #expect(threw)
        let bad = dir.appendingPathComponent("bad.wav"); try Data("RIFF....WAVEjunk".utf8).write(to: bad)
        let before = try Data(contentsOf: bad)
        let threw2 = didThrow { try WavCueWriter.write(cues: [FileCue(frame: 1)], to: bad, keepBackup: false) }
        #expect(threw2)
        let unchanged = try Data(contentsOf: bad)
        #expect(unchanged == before)
    }

    @Test func importAtIndexTimeThenWriteDoesNotReembed() async throws {
        let dir = TestSupport.tempDir()
        let url = dir.appendingPathComponent("loop.wav")
        try makeWav(cues: [FileCue(frame: 100, label: "A")]).write(to: url)
        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })

        var sample = try #require(store.loadSamples().first)
        #expect(store.cues(sampleID: sample.id).map(\.positionFrames) == [100])
        #expect(store.cues(sampleID: sample.id)[0].fileSynced)

        let editor = CueEditor(store: store)
        try editor.add(sampleID: sample.id, frame: 900, label: "B")
        #expect(store.cuesDirty(sampleID: sample.id))
        try store.writeCuesToFile(sample: sample, keepBackup: false)
        #expect(CueFileReader.read(url: url).map(\.frame) == [100, 900])
        #expect(!store.cuesDirty(sampleID: sample.id))
        #expect(store.cues(sampleID: sample.id).allSatisfy { $0.fileSynced })

        // The file changed on disk, but the DB knows: a rescan must not re-embed it.
        let r = try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        #expect(r.unchanged == 1 && r.changed == 0 && store.pendingCount() == 0)
        sample = try #require(store.loadSamples().first)
        #expect(sample.cueCount == 2 && sample.status == .ok)
    }

    @Test func editorUndoRedo() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/c")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "a.wav", size: 1, mtime: 1)]) { _ in nil }
        let id = store.pendingJobs(limit: 1)[0].id
        let editor = CueEditor(store: store)

        let cue = try editor.add(sampleID: id, frame: 100, label: "x")
        try editor.move(id: cue.id, to: 400)
        try editor.rename(id: cue.id, to: "y")
        #expect(store.cue(id: cue.id)?.positionFrames == 400 && store.cue(id: cue.id)?.label == "y")
        try editor.undo(); #expect(store.cue(id: cue.id)?.label == "x")
        try editor.undo(); #expect(store.cue(id: cue.id)?.positionFrames == 100)
        try editor.redo(); #expect(store.cue(id: cue.id)?.positionFrames == 400)
        try editor.remove(id: cue.id); #expect(store.cue(id: cue.id) == nil)
        try editor.undo(); #expect(store.cue(id: cue.id)?.positionFrames == 400)
        try editor.undo(); try editor.undo(); try editor.undo()
        #expect(store.cue(id: cue.id) == nil && !editor.canUndo && editor.canRedo)
        // Persisted: a fresh read of the DB sees the same final state.
        #expect(store.cues(sampleID: id).isEmpty)
    }
}

private final class OutcomeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CueFileSync.Outcome] = []
    func add(_ o: CueFileSync.Outcome) { lock.lock(); items.append(o); lock.unlock() }
    var all: [CueFileSync.Outcome] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct CueFileSyncTests {
    private func library(files: [String]) throws -> (LibraryStore, URL) {
        let dir = TestSupport.tempDir()
        for f in files {
            if f.hasSuffix(".wav") { try makeWav().write(to: dir.appendingPathComponent(f)) }
            else { try Data(count: 64).write(to: dir.appendingPathComponent(f)) }
        }
        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        return (store, dir)
    }

    @Test func editsAreWrittenToTheWavAfterTheDebounce() async throws {
        let (store, dir) = try library(files: ["a.wav"])
        let log = OutcomeLog()
        let sync = CueFileSync(store: store, delay: 0.05) { log.add($0) }
        let sample = try #require(store.loadSamples().first)
        let editor = CueEditor(store: store)

        try editor.add(sampleID: sample.id, frame: 100); sync.markChanged(sampleID: sample.id)
        try editor.add(sampleID: sample.id, frame: 700, label: "snare"); sync.markChanged(sampleID: sample.id)
        try await Task.sleep(for: .milliseconds(500))

        let url = dir.appendingPathComponent("a.wav")
        #expect(CueFileReader.read(url: url).map(\.frame) == [100, 700])
        #expect(CueFileReader.read(url: url).last?.label == "snare")
        #expect(log.all == [.written(sampleID: sample.id)], "two quick edits coalesce into one write")
        #expect(!store.cuesDirty(sampleID: sample.id))

        // Deleting every cue clears them from the file as well.
        for cue in store.cues(sampleID: sample.id) { try editor.remove(id: cue.id) }
        sync.markChanged(sampleID: sample.id)
        sync.flush()
        #expect(CueFileReader.read(url: url).isEmpty)
    }

    @Test func flushWritesPendingEditsImmediately() throws {
        let (store, dir) = try library(files: ["a.wav"])
        let sync = CueFileSync(store: store, delay: 60)
        let sample = try #require(store.loadSamples().first)
        try CueEditor(store: store).add(sampleID: sample.id, frame: 321)
        sync.markChanged(sampleID: sample.id)
        sync.flush()
        #expect(CueFileReader.read(url: dir.appendingPathComponent("a.wav")).map(\.frame) == [321])
    }

    @Test func otherFormatsStayAppOnlyAndUntouched() async throws {
        let (store, dir) = try library(files: ["b.aif"])
        let log = OutcomeLog()
        let sync = CueFileSync(store: store, delay: 0.02) { log.add($0) }
        let sample = try #require(store.loadSamples().first)
        try CueEditor(store: store).add(sampleID: sample.id, frame: 5)
        sync.markChanged(sampleID: sample.id)
        try await Task.sleep(for: .milliseconds(300))
        #expect(log.all == [.appOnly(sampleID: sample.id)])
        #expect(try Data(contentsOf: dir.appendingPathComponent("b.aif")) == Data(count: 64))
        #expect(store.cues(sampleID: sample.id).count == 1)
    }

    @Test func leftoverUnsavedCuesAreSyncedOnStartup() throws {
        let (store, dir) = try library(files: ["a.wav"])
        let sample = try #require(store.loadSamples().first)
        try CueEditor(store: store).add(sampleID: sample.id, frame: 42)   // "previous session": never written
        #expect(store.dirtyCueSampleIDs().isEmpty, "pending samples are not eligible until indexed")
        try store.db.run("UPDATE samples SET status = 'ok' WHERE id = ?", [.int(sample.id)])
        let sync = CueFileSync(store: store, delay: 0.01)
        sync.syncAllDirty()
        sync.flush()
        #expect(CueFileReader.read(url: dir.appendingPathComponent("a.wav")).map(\.frame) == [42])
    }
}
