import Foundation
import Testing
@testable import ClapCore

@Suite struct MelodyPatternTests {
    private func pattern(bars: Int = 1) -> MelodyPattern {
        var p = MelodyPattern()
        p.addTrack(sampleID: 1, label: "Pad")
        p.setBars(bars)
        return p
    }

    @Test func tracksStopAtTheLimitAndCanBeRemoved() {
        var p = MelodyPattern()
        for i in 0..<MelodyPattern.maxTracks {
            let added = p.addTrack(sampleID: Int64(i), label: "t\(i)")
            #expect(added)
        }
        let overflow = p.addTrack(sampleID: 99, label: "extra")
        #expect(!overflow, "the melody holds only a few sounds")
        p.removeTrack(at: 0)
        p.removeTrack(at: 40)                                  // out of range: ignored
        #expect(p.tracks.count == MelodyPattern.maxTracks - 1)
    }

    @Test func aTrackCanWaitForItsSound() {
        var p = MelodyPattern()
        p.addTrack(sampleID: nil, label: "Track 1")
        #expect(p.tracks[0].sampleID == nil && p.tracks[0].rootNote == MelodyTrack.defaultRoot)
    }

    @Test func notesStayInsideThePatternAndTheKeyboard() throws {
        var p = pattern()
        let added = p.addNote(track: 0, pitch: 300, start: -3, length: 100)
        let id = try #require(added)
        let note = try #require(p.tracks[0].notes.first { $0.id == id })
        #expect(note.pitch == 127, "pitch is clamped to the MIDI range")
        #expect(note.start == 0 && note.end == 16, "a note never runs past the end of the pattern")
        let late = p.addNote(track: 0, pitch: 60, start: 16, length: 1)
        #expect(late == nil, "a note starting after the end is refused")
        let nowhere = p.addNote(track: 5, pitch: 60, start: 0)
        #expect(nowhere == nil, "no such track")
        let empty = p.addNote(track: 0, pitch: 60, start: 2, length: 0)
        let tiny = try #require(empty)
        #expect(p.tracks[0].notes.first { $0.id == tiny }?.length == MelodyNote.minLength, "a note is never empty")
    }

    @Test func drawingOverANoteOfTheSamePitchReplacesIt() throws {
        var p = pattern()
        p.addNote(track: 0, pitch: 60, start: 0, length: 4)
        p.addNote(track: 0, pitch: 64, start: 0, length: 4)
        p.addNote(track: 0, pitch: 60, start: 2, length: 4)
        let sameRow = p.tracks[0].notes.filter { $0.pitch == 60 }
        #expect(sameRow.count == 1 && sameRow[0].start == 2, "two notes on one row cannot overlap")
        #expect(p.tracks[0].notes.contains { $0.pitch == 64 }, "other pitches are left alone")
        p.addNote(track: 0, pitch: 60, start: 6, length: 2)
        #expect(p.tracks[0].notes.filter { $0.pitch == 60 }.count == 2, "side by side is fine")
    }

    @Test func notesCanBeMovedResizedAndRemoved() throws {
        var p = pattern()
        let added = p.addNote(track: 0, pitch: 60, start: 4, length: 2)
        let id = try #require(added)
        p.moveNote(track: 0, id: id, pitch: 67, start: 10)
        var note = try #require(p.tracks[0].notes.first)
        #expect(note.pitch == 67 && note.start == 10 && note.length == 2)
        p.moveNote(track: 0, id: id, pitch: 67, start: 15)
        note = try #require(p.tracks[0].notes.first)
        #expect(note.start == 15 && note.end == 16, "moved to the edge, it is shortened to fit")
        p.resizeNote(track: 0, id: id, length: 0)
        #expect(p.tracks[0].notes[0].length == MelodyNote.minLength)
        p.resizeNote(track: 0, id: id, length: 50)
        #expect(p.tracks[0].notes[0].end == 16)
        p.removeNote(track: 0, id: id)
        #expect(p.tracks[0].notes.isEmpty)
    }

    @Test func shorteningThePatternDropsAndTrimsNotesButLengtheningKeepsThem() throws {
        var p = pattern(bars: 4)
        p.addNote(track: 0, pitch: 60, start: 40, length: 4)      // bar 3
        p.addNote(track: 0, pitch: 62, start: 14, length: 4)      // crosses the bar line
        p.setBars(2)
        #expect(p.tracks[0].notes.count == 1, "notes after the new end are dropped")
        let kept = try #require(p.tracks[0].notes.first)
        #expect(kept.pitch == 62 && kept.end == 18)
        p.setBars(1)
        #expect(p.tracks[0].notes[0].end == 16, "a note crossing the new end is trimmed")
        p.setBars(4)
        #expect(p.tracks[0].notes[0].end == 16, "growing again does not bring anything back")
        #expect(p.stepCount == 64)
    }

    @Test func barsAreKeptInRange() {
        var p = MelodyPattern()
        p.setBars(0); #expect(p.bars == 1)
        p.setBars(10_000); #expect(p.bars == MelodyPattern.maxBars)
    }

    @Test func thePatternGrowsToHoldALongerSequence() {
        var p = MelodyPattern()
        p.growBars(toFit: 16);  #expect(p.bars == 1, "an exact bar needs no more")
        p.growBars(toFit: 16.5); #expect(p.bars == 2)
        p.growBars(toFit: 5);   #expect(p.bars == 2, "growing never shrinks")
        p.growBars(toFit: 16 * 100); #expect(p.bars == MelodyPattern.maxBars)
    }

    @Test func savedPatternsComeBackSafeToPlay() throws {
        var p = pattern(bars: 2)
        p.tracks[0].rootNote = 52
        p.addNote(track: 0, pitch: 55, start: 1.5, length: 0.5, velocity: 0.4)
        let again = try JSONDecoder().decode(MelodyPattern.self, from: JSONEncoder().encode(p))
        #expect(again == p, "everything survives a round trip")

        // A saved file can hold anything: a length no one could set, then values out of range.
        let json = try #require(String(data: JSONEncoder().encode(p), encoding: .utf8)).replacingOccurrences(of: "\"bars\":2", with: "\"bars\":999")
        var bad = try JSONDecoder().decode(MelodyPattern.self, from: Data(json.utf8))
        #expect(bad.bars == 999, "decoding trusts the file; sanitized() is what makes it safe")
        bad.tracks[0].volume = .nan
        bad.tracks[0].rootNote = -4
        bad.tracks[0].notes[0].pitch = 400
        bad.tracks[0].notes[0].velocity = 7
        bad.tracks[0].notes[0].length = .infinity
        bad.tracks += (0..<10).map { MelodyTrack(sampleID: Int64($0), label: "x") }
        let safe = bad.sanitized()
        #expect(safe.bars == MelodyPattern.maxBars && safe.tracks.count == MelodyPattern.maxTracks)
        #expect(safe.tracks[0].volume == MelodyTrack.defaultVolume && safe.tracks[0].rootNote == 0)
        let note = safe.tracks[0].notes[0]
        #expect(note.pitch == 127 && note.velocity == 1 && note.end <= Double(safe.stepCount))
    }
}

@Suite struct NoteNameTests {
    @Test func aFrequencyBecomesTheNearestMidiNote() {
        #expect(NoteNames.midiNote(forHz: 440) == 69, "concert A")
        #expect(NoteNames.midiNote(forHz: 261.63) == 60, "middle C")
        #expect(NoteNames.midiNote(forHz: 450) == 69, "a little sharp is still an A")
        #expect(NoteNames.midiNote(forHz: 10) == nil && NoteNames.midiNote(forHz: 20_000) == nil, "outside what a sample can sensibly have")
    }

    @Test func midiNotesHaveTheNamesMusiciansUse() {
        #expect(NoteNames.name(midi: 60) == "C4" && NoteNames.name(midi: 69) == "A4" && NoteNames.name(midi: 61) == "C#4")
        #expect(NoteNames.name(midi: 0) == "C-1" && NoteNames.name(midi: 127) == "G9")
        #expect(NoteNames.name(midi: 300) == "G9" && NoteNames.name(midi: -5) == "C-1", "out of range is held at the ends")
        #expect(NoteNames.name(forHz: 440) == "A4", "the older name-from-frequency still agrees")
    }

    @Test func blackKeysAreTheSharps() {
        #expect([61, 63, 66, 68, 70].allSatisfy { NoteNames.isBlackKey($0) })
        #expect([60, 62, 64, 65, 67, 69, 71].allSatisfy { !NoteNames.isBlackKey($0) })
    }
}

@Suite struct MelodyKeepingSoundsTests {
    @Test func aTrackWhoseSampleIsGoneKeepsItsNotesAndWaitsForANewSound() throws {
        var p = MelodyPattern()
        p.addTrack(sampleID: 1, label: "Here", rootNote: 50)
        p.addTrack(sampleID: 2, label: "Gone", rootNote: 52)
        p.addTrack(sampleID: nil, label: "Empty")
        p.addNote(track: 1, pitch: 60, start: 3, length: 2)
        p.setBars(2)

        let kept = p.keepingSounds { $0 == 1 }
        #expect(kept.tracks.map(\.sampleID) == [1, nil, nil], "only the sound that is still there stays")
        #expect(kept.tracks[1].notes == p.tracks[1].notes && kept.tracks[1].label == "Gone" && kept.tracks[1].rootNote == 52,
                "the notes the user wrote are never thrown away")
        #expect(kept.bars == 2 && kept.tracks.count == 3)
        #expect(p.keepingSounds { _ in true } == p, "nothing changes when every sound is available")
    }
}
