import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct FileMetadataTests {
    private func le32(_ v: Int) -> Data { var d = Data(); for i in 0..<4 { d.append(UInt8((v >> (8 * i)) & 0xFF)) }; return d }

    private func chunk(_ id: String, _ payload: Data) -> Data {
        var d = Data(id.utf8); d.append(le32(payload.count)); d.append(payload)
        if payload.count & 1 == 1 { d.append(0) }
        return d
    }

    private func info(_ entries: [(String, String)]) -> Data {
        var inner = Data("INFO".utf8)
        for (id, text) in entries { inner.append(chunk(id, Data(text.utf8) + [0])) }
        return chunk("LIST", inner)
    }

    /// A short WAV with chunks before and after the audio.
    private func wav(before: [Data] = [], after: [Data] = [], frames: Int = 100) -> Data {
        var fmt = Data(); fmt.append(contentsOf: [1, 0, 1, 0]); fmt.append(le32(8000)); fmt.append(le32(16000)); fmt.append(contentsOf: [2, 0, 16, 0])
        var audio = Data(); for i in 0..<frames { audio.append(contentsOf: [UInt8(i & 0xFF), UInt8((i * 7) & 0x7F)]) }
        var body = Data("WAVE".utf8)
        body.append(chunk("fmt ", fmt))
        for c in before { body.append(c) }
        body.append(chunk("data", audio))
        for c in after { body.append(c) }
        var file = Data("RIFF".utf8); file.append(le32(body.count)); file.append(body)
        return file
    }

    private func file(_ data: Data, named name: String = "a.wav") throws -> URL {
        let url = TestSupport.tempDir().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: reading

    @Test func ucsNamesAreRecognisedAndOrdinaryNamesAreNot() {
        let ucs = UCSName.parse(fileName: "DOORWood_Door Slam_BOOM_Library.wav")
        #expect(ucs?.ucsID == "DOORWood" && ucs?.title == "Door Slam" && ucs?.creator == "BOOM" && ucs?.source == "Library")
        #expect(UCSName.parse(fileName: "AIRBrst_Vendor-Air Burst_ABC.wav")?.title == "Air Burst", "a vendor category in front is dropped")
        #expect(UCSName.parse(fileName: "DOORWood-Heavy_Door Slam_BOOM.wav")?.ucsID == "DOORWood", "a user category follows the CatID")
        #expect(UCSName.parse(fileName: "KICK_Heavy_Sound.wav") == nil)
        #expect(UCSName.parse(fileName: "kick_heavy_sound.wav") == nil)
        #expect(UCSName.parse(fileName: "DOORWood_Slam.wav") == nil, "a creator is needed")
        #expect(UCSName.parse(fileName: "Snare 01.wav") == nil)
    }

    @Test func keywordsAreSplitTidiedAndDeduplicated() {
        #expect(FileMetadata.splitKeywords("door; Slam, wood\nDOOR ;; ") == ["door", "Slam", "wood"])
        #expect(FileMetadata.splitKeywords("").isEmpty)
    }

    @Test func iXMLInfoAndBextAreMergedWithiXMLFirst() throws {
        var bext = Data(count: 602)
        bext.replaceSubrange(0..<9, with: Data("Bext note".utf8))
        bext.replaceSubrange(256..<266, with: Data("Recorder X".utf8))
        bext.replaceSubrange(320..<330, with: Data("2024-05-01".utf8))
        let ixml = "<BWFXML><USER><USER_DESCRIPTION>A heavy door &amp; its echo</USER_DESCRIPTION><USER_KEYWORDS>door; echo</USER_KEYWORDS>"
            + "<CATEGORY>DOORS</CATEGORY><SUBCATEGORY>Wood</SUBCATEGORY></USER><NOTE>ignored, the description came first</NOTE></BWFXML>"
        let url = try file(wav(before: [chunk("bext", bext)],
                               after: [chunk("iXML", Data(ixml.utf8)),
                                       info([("INAM", "Door Slam"), ("ICMT", "info comment"), ("IKEY", "wood"), ("IART", "Ann"), ("IPRD", "Doors Vol 1")])]),
                           named: "DOORWood_Door Slam_ANN_Doors.wav")
        let meta = FileMetadataReader.read(url: url)
        #expect(meta.description == "A heavy door & its echo", "iXML wins over INFO and bext")
        #expect(meta.keywords == ["door", "echo"] && meta.category == "DOORS" && meta.subcategory == "Wood")
        #expect(meta.title == "Door Slam" && meta.creator == "Ann" && meta.source == "Doors Vol 1", "INFO fills what iXML lacks")
        #expect(meta.originator == "Recorder X" && meta.date == "2024-05-01", "bext fills the rest")
        #expect(meta.ucsID == "DOORWood", "and the name gives its UCS category")
    }

    @Test func aPlaceInACommentIsNotADescription() throws {
        let url = try file(wav(after: [info([("ICMT", "+51.5000-000.1000/")])]))
        #expect(FileMetadataReader.read(url: url).description.isEmpty)
    }

    @Test func plainAndMissingFilesGiveNothing() throws {
        #expect(FileMetadataReader.read(url: try file(wav())).isEmpty)
        #expect(FileMetadataReader.read(url: URL(fileURLWithPath: "/nonexistent/x.wav")).isEmpty)
    }

    // MARK: writing

    @Test func tagsAreWrittenAfterTheAudioAndEverythingElseIsKept() throws {
        let original = wav(after: [info([("INAM", "Keep me"), ("IGNR", "Old"), ("IKEY", "old")])])
        let url = try file(original)
        try WavMetadataWriter.write(category: "Kick", keywords: ["punchy", "dry", "Dark"], to: url, keepBackup: false)
        let written = try Data(contentsOf: url)
        let chunks = WavChunks.parse(written)
        #expect(chunks.map(\.id) == ["fmt ", "data", "LIST"], "the old list was replaced, not added to")
        #expect(Int(written.le32(4)) == written.count - 8 && written.count % 2 == 0)
        let meta = FileMetadataReader.read(url: url)
        #expect(meta.title == "Keep me" && meta.category == "Kick" && meta.keywords == ["punchy", "dry", "Dark"])
        let dataBefore = WavChunks.parse(original).first { $0.id == "data" }!, dataAfter = chunks.first { $0.id == "data" }!
        #expect(original[dataBefore.dataStart..<(dataBefore.dataStart + dataBefore.size)] == written[dataAfter.dataStart..<(dataAfter.dataStart + dataAfter.size)])
        #expect(try AVAudioFile(forReading: url).length == 100)
    }

    @Test func aListInTheMiddleStopsBeingReadAndTheAudioDoesNotMove() throws {
        let original = wav(before: [info([("ICMT", "before the audio"), ("IGNR", "Old")])], after: [chunk("junk", Data([1, 2, 3]))])
        let url = try file(original)
        try WavMetadataWriter.write(category: "Snare", keywords: [], to: url, keepBackup: false)
        let written = try Data(contentsOf: url)
        let ids = WavChunks.parse(written).map(\.id)
        #expect(ids == ["fmt ", "JUNK", "data", "junk", "LIST"])
        let before = WavChunks.parse(original).first { $0.id == "data" }!
        #expect(WavChunks.parse(written).first { $0.id == "data" }?.headerStart == before.headerStart)
        let meta = FileMetadataReader.read(url: url)
        #expect(meta.category == "Snare" && meta.keywords.isEmpty)
        #expect(meta.description == "before the audio", "its entries moved into the new list")
        #expect(try AVAudioFile(forReading: url).length == 100)
    }

    @Test func writingAgainReplacesRatherThanPiles() throws {
        let url = try file(wav())
        try WavMetadataWriter.write(category: "Kick", keywords: ["a"], to: url, keepBackup: false)
        let once = try Data(contentsOf: url).count
        try WavMetadataWriter.write(category: "Kick", keywords: ["a"], to: url, keepBackup: false)
        #expect(try Data(contentsOf: url).count == once)
        try WavMetadataWriter.write(category: nil, keywords: [], to: url, keepBackup: false)
        let meta = FileMetadataReader.read(url: url)
        #expect(meta.category.isEmpty && meta.keywords.isEmpty)
        #expect(WavChunks.parse(try Data(contentsOf: url)).map(\.id) == ["fmt ", "data"], "nothing left to say, nothing written")
    }

    @Test func oddSizedAudioIsPaddedBeforeTheList() throws {
        var fmt = Data(); fmt.append(contentsOf: [1, 0, 1, 0]); fmt.append(le32(8000)); fmt.append(le32(8000)); fmt.append(contentsOf: [1, 0, 8, 0])
        var body = Data("WAVE".utf8)
        body.append(chunk("fmt ", fmt)); body.append(chunk("data", Data([1, 2, 3])))
        var odd = Data("RIFF".utf8); odd.append(le32(body.count)); odd.append(body)
        let oddURL = try file(odd, named: "odd.wav")
        try WavMetadataWriter.write(category: "Hi-hat", keywords: ["x"], to: oddURL, keepBackup: false)
        let written = try Data(contentsOf: oddURL)
        #expect(Int(written.le32(4)) == written.count - 8)
        #expect(WavChunks.parse(written).map(\.id) == ["fmt ", "data", "LIST"])
        #expect(FileMetadataReader.read(url: oddURL).category == "Hi-hat")
    }

    @Test func aBackupKeepsTheOriginalAndOtherFilesAreRefused() throws {
        let original = wav()
        let url = try file(original)
        let backup = try WavMetadataWriter.write(category: "Kick", keywords: [], to: url, keepBackup: true)
        let kept = try backup.map { try Data(contentsOf: $0) }
        #expect(kept == original)
        #expect(throws: CueWriteError.self) { try WavMetadataWriter.write(category: "Kick", keywords: [], to: try file(original, named: "a.aif"), keepBackup: false) }
        #expect(throws: CueWriteError.self) { try WavMetadataWriter.write(category: "Kick", keywords: [], to: try file(Data("not a wav at all".utf8)), keepBackup: false) }
    }

    // MARK: the library

    @Test func whatFilesSayIsStoredSearchedAndWrittenBack() throws {
        let (store, dir) = try TestSupport.makeStore()
        let root = try store.addRoot(path: dir.path)
        try wav(after: [info([("IKEY", "wood; creak"), ("ICMT", "Heavy 100% door")])]).write(to: dir.appendingPathComponent("a.wav"))
        try wav().write(to: dir.appendingPathComponent("b.wav"))
        _ = try store.sync(rootID: root.id, scanned: ["a.wav", "b.wav"].map { ScannedFile(relPath: $0, size: 10, mtime: 1) }) { _ in nil }
        try store.save(results: store.pendingJobs(limit: 10).map {
            .success(id: $0.id, duration: 0.01, sampleRate: 8000, channels: 1, embedding: [1, 0], fingerprint: nil, modelVersion: "m1")
        })
        let samples = store.loadSamples()
        let a = samples.first { $0.name.hasPrefix("a") }!, b = samples.first { $0.name.hasPrefix("b") }!
        try store.saveFileMetadata(samples.map { ($0.id, FileMetadataReader.read(url: $0.url)) })

        #expect(store.fileMetadata(sampleID: a.id)?.keywords == ["wood", "creak"] && store.fileMetadata(sampleID: b.id) == nil)
        #expect(store.samplesWithFileMetadata(matching: "creak") == [a.id])
        #expect(store.samplesWithFileMetadata(matching: "WOOD") == [a.id], "any case")
        #expect(store.samplesWithFileMetadata(matching: "100%") == [a.id] && store.samplesWithFileMetadata(matching: "%").count == 1, "wildcards are literal")
        #expect(store.samplesWithFileMetadata(matching: "nothing like this").isEmpty)
        #expect(store.fileKeywords(sampleIDs: [a.id, b.id]) == [a.id: ["wood", "creak"]])

        try store.addTag("punchy", to: [b.id])
        try store.setManualCategories([(id: b.id, category: "Kick")])
        let fresh = store.sample(id: b.id)!
        try store.writeTagsToFile(sample: fresh, keepBackup: false)
        let after = store.sample(id: b.id)!
        let bytes = try Data(contentsOf: b.url).count
        #expect(after.size == Int64(bytes), "the library knows the file changed")
        #expect(store.fileMetadata(sampleID: b.id)?.category == "Kick" && store.fileMetadata(sampleID: b.id)?.keywords == ["punchy"])
        #expect(WavInfo.category(of: b.url) == "Kick", "what the Squid export reads")
    }
}
