import Foundation
import Testing
@testable import ClapCore

@Suite struct MelodyStoreTests {
    private func longMelody(notes: Int) -> MelodyPattern {
        var p = MelodyPattern()
        p.addTrack(sampleID: 3, label: "Lead", rootNote: 57)
        p.growBars(toFit: Double(notes) * 2)
        p.setNotes(track: 0, (0..<notes).map { MelodyNote(pitch: 40 + $0 % 40, start: Double($0) * 2, length: 1.5, velocity: 0.7) })
        return p
    }

    @Test func aLongMelodyComesBackExactlyAsSaved() throws {
        let url = TestSupport.tempDir().appendingPathComponent("melody.json")
        let melody = longMelody(notes: 30_000)
        try MelodyStore.save(melody, to: url)
        let back = try #require(MelodyStore.load(from: url))
        #expect(back == melody, "every note, the sound and the length survive a restart")
        #expect(back.bars > 1000, "the test melody really is long")
    }

    @Test func savingAgainReplacesTheEarlierMelody() throws {
        let url = TestSupport.tempDir().appendingPathComponent("melody.json")
        try MelodyStore.save(longMelody(notes: 500), to: url)
        let shorter = longMelody(notes: 5)
        try MelodyStore.save(shorter, to: url)
        #expect(MelodyStore.load(from: url) == shorter)
    }

    @Test func nothingOrGarbageIsNoMelodyRatherThanAnError() throws {
        let dir = TestSupport.tempDir()
        #expect(MelodyStore.load(from: dir.appendingPathComponent("missing.json")) == nil, "a first launch has nothing saved")
        let junk = dir.appendingPathComponent("junk.json")
        try Data("not a melody".utf8).write(to: junk)
        #expect(MelodyStore.load(from: junk) == nil, "a damaged file does not stop the app starting")
    }

    @Test func whatIsLoadedIsMadeSafeToPlay() throws {
        let url = TestSupport.tempDir().appendingPathComponent("melody.json")
        var melody = longMelody(notes: 3)
        melody.tracks[0].volume = 40
        try MelodyStore.save(melody, to: url)
        let text = try #require(String(data: Data(contentsOf: url), encoding: .utf8)).replacingOccurrences(of: "\"bars\":1", with: "\"bars\":999999999")
        try Data(text.utf8).write(to: url)
        let back = try #require(MelodyStore.load(from: url))
        #expect(back.bars == MelodyPattern.maxBars && back.tracks[0].volume == 1, "a hand-edited file cannot ask for the impossible")
    }
}
