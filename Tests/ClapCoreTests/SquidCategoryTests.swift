import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidCategoryTests {
    private func wavFile(_ dir: URL, _ name: String = "a.wav", frames: Int = 4410) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try makeWav(frames: frames).write(to: url)
        return url
    }

    @Test func aGenreIsAddedAfterTheAudioWithoutChangingIt() throws {
        let dir = TestSupport.tempDir()
        let url = try wavFile(dir)
        let before = try Data(contentsOf: url)
        try WavInfo.appendGenre("Kick", to: url)
        let after = try Data(contentsOf: url)

        #expect(WavInfo.genre(of: url) == "Kick")
        #expect(after.count > before.count && after.prefix(4) == before.prefix(4))
        #expect(after[12..<before.count] == before[12..<before.count], "every existing chunk is as it was")
        #expect(Int(after.le32(4)) == after.count - 8, "the RIFF length covers the new chunk")
        let chunks = WavChunks.parse(after)
        #expect(chunks.map(\.id) == ["fmt ", "data", "LIST"])
        #expect(chunks.last?.end == after.count)
        #expect(try AVAudioFile(forReading: url).length == 4410, "still reads as the same audio")
    }

    @Test func oddLengthNamesArePaddedToAnEvenChunk() throws {
        let dir = TestSupport.tempDir()
        for genre in ["Bass", "Hi-hat", "Brass & Winds"] {
            let url = try wavFile(dir, "\(genre.count).wav")
            try WavInfo.appendGenre(genre, to: url)
            let data = try Data(contentsOf: url)
            #expect(data.count % 2 == 0 && Int(data.le32(4)) == data.count - 8)
            #expect(WavInfo.genre(of: url) == genre)
        }
    }

    @Test func aFileWithoutATagHasNoGenre() throws {
        #expect(WavInfo.genre(of: try wavFile(TestSupport.tempDir())) == nil)
        #expect(WavInfo.genre(of: TestSupport.tempDir().appendingPathComponent("missing.wav")) == nil)
    }

    @Test func onlyTheAppsCategoriesCount() throws {
        let dir = TestSupport.tempDir()
        func category(_ genre: String) throws -> String? {
            let url = try wavFile(dir, "\(UUID().uuidString).wav")
            try WavInfo.appendGenre(genre, to: url)
            return WavInfo.category(of: url)
        }
        #expect(try category("Snare") == "Snare")
        #expect(try category("hi-hat") == "Hi-hat", "spelled the way the app spells it")
        #expect(try category("Drum Loop") == "Drum Loop")
        #expect(try category("Trip Hop") == nil, "some other genre")
        #expect(try category(SoundCategories.fieldRecording) == nil, "never cuts a stick sample into segments")
    }

    @Test func cuesWrittenLaterKeepTheGenre() throws {
        let dir = TestSupport.tempDir()
        let url = try wavFile(dir)
        try WavInfo.appendGenre("Tom", to: url)
        try WavCueWriter.write(cues: [FileCue(frame: 1000, label: "hit")], to: url, keepBackup: false)
        #expect(WavInfo.genre(of: url) == "Tom")
        #expect(CueFileReader.read(url: url) == [FileCue(frame: 1000, label: "hit")])
    }

    @Test func sendingSamplesKeepsTheirCategory() throws {
        let dir = TestSupport.tempDir()
        let stick = TestSupport.tempDir()
        let a = try wavFile(dir, "a.wav", frames: 22_050)
        let request = SquidBankRequest(set: nil, number: 1, name: "Kit", slots: [
            SquidSource(file: a, name: "Kick", category: "Kick"), SquidSource(file: a, name: "Plain")])
        let bank = try SquidExporter.export(request, toVolume: stick)
        #expect(WavInfo.genre(of: bank.appendingPathComponent("1/Kick.wav")) == "Kick")
        #expect(WavInfo.genre(of: bank.appendingPathComponent("2/Plain.wav")) == nil, "no category, no tag")
        let file = try AVAudioFile(forReading: bank.appendingPathComponent("1/Kick.wav"))
        #expect(file.fileFormat.sampleRate == 44_100 && file.fileFormat.channelCount == 1 && file.length > 22_000)

        try SquidExporter.add([SquidSource(file: a, name: "Added", category: "Pad")], set: nil, number: 1, toVolume: stick)
        #expect(WavInfo.genre(of: bank.appendingPathComponent("3/Added.wav")) == "Pad")
        let pooled = try SquidExporter.exportToPool([SquidSource(file: a, name: "Loop", category: "Drum Loop")], toVolume: stick)
        #expect(WavInfo.genre(of: pooled[0]) == "Drum Loop")
    }

    @Test func aStickSampleTakesTheCategoryItWasSentWith() async throws {
        let dir = TestSupport.tempDir()
        for folder in ["stick", "library"] {
            let wav = dir.appendingPathComponent(folder).appendingPathComponent("Bank 1/1/hit.wav")
            try FileManager.default.createDirectory(at: wav.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeTestWav(wav, seconds: 0.5) { Float(sin($0 * 2 * .pi * 440)) * 0.5 }
            try WavInfo.appendGenre("Cowbell", to: wav)
        }
        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        for (folder, transient) in [("stick", true), ("library", false)] {
            let root = dir.appendingPathComponent(folder)
            let record = try store.addRoot(path: root.path, transient: transient)
            try store.sync(rootID: record.id, scanned: FolderScanner.scan(root: root)) { _ in nil }
        }
        _ = await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })

        let onStick = try #require(store.loadTransientSamples().first)
        #expect(onStick.categoryManual == "Cowbell" && onStick.effectiveCategory == "Cowbell")
        let inLibrary = try #require(store.loadSamples().first)
        #expect(inLibrary.categoryManual == nil, "a library file's own genre tag is none of our business")
    }
}
