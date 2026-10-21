import Foundation
import Testing
@testable import ClapCore

/// Builds Standard MIDI Files byte by byte, so the reader is checked against the format and not against itself.
enum Midi {
    static func vlq(_ value: Int) -> [UInt8] {
        var v = value, out = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 { out.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
        return out
    }
    static func event(_ delta: Int, _ bytes: UInt8...) -> [UInt8] { vlq(delta) + bytes }
    static func meta(_ delta: Int, type: UInt8, _ data: [UInt8]) -> [UInt8] { vlq(delta) + [0xFF, type] + vlq(data.count) + data }
    static func name(_ text: String) -> [UInt8] { meta(0, type: 0x03, Array(text.utf8)) }
    static let endOfTrack = meta(0, type: 0x2F, [])
    static func tempo(_ microsPerBeat: Int) -> [UInt8] {
        meta(0, type: 0x51, [UInt8(microsPerBeat >> 16 & 0xFF), UInt8(microsPerBeat >> 8 & 0xFF), UInt8(microsPerBeat & 0xFF)])
    }
    static func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
        let n = body.count
        return Array(id.utf8) + [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + body
    }
    static func file(format: Int = 1, division: Int = 480, tracks: [[UInt8]]) -> Data {
        let header: [UInt8] = [UInt8(format >> 8), UInt8(format & 0xFF), UInt8(tracks.count >> 8), UInt8(tracks.count & 0xFF),
                               UInt8(division >> 8 & 0xFF), UInt8(division & 0xFF)]
        return Data(chunk("MThd", header) + tracks.flatMap { chunk("MTrk", $0) })
    }
}

@Suite struct MidiFileTests {
    @Test func notesBecomeStepsAndEachTrackStaysSeparate() throws {
        let tempoTrack = Midi.tempo(500_000) + Midi.endOfTrack
        let lead = Midi.name("Lead")
            + Midi.event(0, 0x90, 60, 100) + Midi.event(240, 0x80, 60, 0)        // an eighth note: 2 steps long, at 0
            + Midi.event(240, 0x90, 64, 64) + Midi.event(480, 0x80, 64, 0)       // starts at tick 480 = step 4
            + Midi.endOfTrack
        let bass = Midi.name("Bass") + Midi.event(960, 0x91, 36, 127) + Midi.event(1920, 0x81, 36, 0) + Midi.endOfTrack
        let tracks = try MidiFile.parse(Midi.file(tracks: [tempoTrack, lead, bass]))
        #expect(tracks.map(\.name) == ["Lead", "Bass"], "a track with no notes (the tempo map) is left out")
        #expect(tracks[0].notes == [MidiNote(pitch: 60, start: 0, length: 2, velocity: 100 / 127),
                                    MidiNote(pitch: 64, start: 4, length: 4, velocity: 64 / 127)])
        #expect(tracks[1].notes == [MidiNote(pitch: 36, start: 8, length: 16, velocity: 1)], "two beats in, four beats long")
        #expect(tracks[1].endStep == 24)
    }

    @Test func tempoInTheFileDoesNotChangeTheSteps() throws {
        let slow = Midi.tempo(1_000_000) + Midi.event(0, 0x90, 60, 90) + Midi.event(480, 0x80, 60, 0) + Midi.endOfTrack
        let fast = Midi.tempo(250_000) + Midi.event(0, 0x90, 60, 90) + Midi.event(480, 0x80, 60, 0) + Midi.endOfTrack
        let a = try MidiFile.parse(Midi.file(tracks: [slow])), b = try MidiFile.parse(Midi.file(tracks: [fast]))
        #expect(a == b && a[0].notes[0].length == 4, "the project tempo decides the speed, not the file")
    }

    @Test func otherTicksPerBeatAreScaled() throws {
        let body = Midi.event(0, 0x90, 60, 100) + Midi.event(96, 0x80, 60, 0) + Midi.endOfTrack
        let tracks = try MidiFile.parse(Midi.file(division: 96, tracks: [body]))
        #expect(tracks[0].notes[0].length == 4, "96 ticks per beat: a beat is four steps")
    }

    @Test func runningStatusAndNoteOnWithZeroVelocityEndNotes() throws {
        // One status byte for several messages; the second note ends with a note-on of velocity 0.
        let body: [UInt8] = [0x00, 0x90, 60, 100,
                             0x78, 62, 100,                // running status: a note-on, 120 ticks later
                             0x78, 60, 0,                  // running status: velocity 0 ends the first note
                             0x78, 62, 0] + Midi.endOfTrack
        let notes = try MidiFile.parse(Midi.file(tracks: [body]))[0].notes
        #expect(notes.map(\.pitch) == [60, 62])
        #expect(notes[0].start == 0 && notes[0].length == 2, "ends at tick 240")
        #expect(notes[1].start == 1 && notes[1].length == 2, "starts at tick 120, ends at 360")
    }

    @Test func otherMessagesAreSkippedWithoutLosingNotes() throws {
        let body = Midi.name("Keys")
            + Midi.event(0, 0xC0, 5)                       // program change: one data byte
            + Midi.event(0, 0xB0, 7, 100)                  // controller
            + Midi.event(0, 0xE0, 0, 64)                   // pitch bend
            + [0x00, 0xF0, 0x03, 0x7E, 0x00, 0xF7]         // system exclusive
            + Midi.meta(0, type: 0x58, [4, 2, 24, 8])      // time signature
            + Midi.event(0, 0x90, 67, 80) + Midi.event(480, 0x80, 67, 0) + Midi.endOfTrack
        let tracks = try MidiFile.parse(Midi.file(tracks: [body]))
        #expect(tracks.count == 1 && tracks[0].notes.map(\.pitch) == [67])
    }

    @Test func aNoteLeftHangingEndsWithTheTrack() throws {
        let body = Midi.event(0, 0x90, 60, 100) + Midi.event(480, 0x90, 64, 100) + Midi.event(480, 0xB0, 7, 100) + Midi.endOfTrack
        let notes = try MidiFile.parse(Midi.file(tracks: [body]))[0].notes
        #expect(notes.map(\.length) == [8, 4], "both stop at the end of the track, 960 ticks in")
    }

    @Test func aNoteThatEndsWhereItStartsIsStillAudible() throws {
        let body = Midi.event(0, 0x90, 60, 100) + Midi.event(0, 0x80, 60, 0) + Midi.endOfTrack
        let notes = try MidiFile.parse(Midi.file(tracks: [body]))[0].notes
        #expect(notes[0].length == MelodyNote.minLength)
    }

    @Test func aSingleTrackFileIsSplitByChannel() throws {
        let body = Midi.event(0, 0x90, 60, 100) + Midi.event(0, 0x91, 40, 100)
            + Midi.event(480, 0x80, 60, 0) + Midi.event(0, 0x81, 40, 0) + Midi.endOfTrack
        let tracks = try MidiFile.parse(Midi.file(format: 0, tracks: [body]))
        #expect(tracks.map(\.name) == ["Channel 1", "Channel 2"], "format 0 keeps every instrument in one track")
        #expect(tracks.map { $0.notes.map(\.pitch) } == [[60], [40]])
    }

    @Test func aCutOffFileKeepsWhatWasRead() throws {
        let body = Midi.event(0, 0x90, 60, 100) + Midi.event(480, 0x80, 60, 0) + Midi.event(0, 0x90, 64, 100)
        var data = Midi.file(tracks: [body])
        data.removeLast(2)                                 // loses part of the last message
        let tracks = try MidiFile.parse(data)
        #expect(tracks.first?.notes.first?.pitch == 60, "a damaged end does not throw away the notes before it")
    }

    @Test func notesAreSortedByStart() throws {
        let body = Midi.event(480, 0x90, 64, 100) + Midi.event(0, 0x80, 64, 0)
            + Midi.event(0, 0x90, 60, 100) + Midi.event(480, 0x80, 60, 0) + Midi.endOfTrack
        let notes = try MidiFile.parse(Midi.file(tracks: [body]))[0].notes
        #expect(notes.map(\.start) == notes.map(\.start).sorted())
    }

    @Test func filesThatAreNotUsableAreRefusedInPlainWords() throws {
        #expect(throws: MidiError.notMidi) { try MidiFile.parse(Data("RIFF....WAVE".utf8)) }
        #expect(throws: MidiError.notMidi) { try MidiFile.parse(Data()) }
        let smpte = Midi.file(division: 0xE728, tracks: [Midi.endOfTrack])         // timed in frames, not beats
        #expect(throws: MidiError.unsupportedTiming) { try MidiFile.parse(smpte) }
        #expect(MidiError.notMidi.errorDescription?.contains("MIDI") == true)
    }
}

@Suite struct MelodyImportTests {
    private func track(_ name: String, notes: [(Int, Double, Double)]) -> MidiTrack {
        MidiTrack(name: name, notes: notes.map { MidiNote(pitch: $0.0, start: $0.1, length: $0.2, velocity: 0.5) })
    }

    @Test func eachMidiTrackBecomesATrackThatCarriesTheChosenSound() {
        let imported = MelodyImport.pattern(from: [track("Lead", notes: [(60, 0, 2), (64, 4, 4)]), track("", notes: [(36, 8, 8)])],
                                            sampleID: 7, bars: 1)
        let p = imported.pattern
        #expect(p.tracks.map(\.label) == ["Lead", "Track 2"], "an unnamed track is numbered")
        #expect(p.tracks.allSatisfy { $0.sampleID == 7 }, "every track starts with the sample picked in the library")
        #expect(p.tracks[0].notes.map(\.pitch) == [60, 64] && p.tracks[0].notes[0].velocity == 0.5)
        #expect(p.bars == 1 && imported.notice == nil)
    }

    @Test func withoutASampleTheTracksWaitForOne() {
        let p = MelodyImport.pattern(from: [track("Lead", notes: [(60, 0, 1)])], sampleID: nil, bars: 1).pattern
        #expect(p.tracks[0].sampleID == nil)
    }

    @Test func aLongerFileMakesThePatternLongerAndAShorterOneKeepsTheChosenLength() {
        let long = track("Lead", notes: [(60, 40, 4)])                 // ends in bar 3
        #expect(MelodyImport.pattern(from: [long], sampleID: 1, bars: 1).pattern.bars == 3, "the whole sequence fits")
        #expect(MelodyImport.pattern(from: [long], sampleID: 1, bars: 4).pattern.bars == 4, "the chosen length is not shortened")
        let short = track("Lead", notes: [(60, 0, 4)])
        #expect(MelodyImport.pattern(from: [short], sampleID: 1, bars: 2).pattern.bars == 2)
    }

    @Test func tooManyTracksSayHowManyWereUsed() {
        let many = (1...6).map { track("T\($0)", notes: [(60, 0, 1)]) }
        let manyResult = MelodyImport.pattern(from: many, sampleID: 1, bars: 1)
        #expect(manyResult.pattern.tracks.count == MelodyPattern.maxTracks)
        #expect(manyResult.notice?.contains("4 of 6") == true, "says how many tracks were used")
    }

    @Test func aLongSequenceIsKeptWholeHoweverManyBarsItTakes() {
        let steps = Double(300 * MelodyPattern.stepsPerBar)               // far past the old 64 bars
        let song = track("Lead", notes: [(60, 0, 1), (62, steps - 4, 2)])
        let result = MelodyImport.pattern(from: [song], sampleID: 1, bars: 1)
        #expect(result.pattern.bars == 300 && result.pattern.tracks[0].notes.count == 2, "the whole sequence fits")
        #expect(result.notice == nil, "nothing was left out")
    }

    @Test func aDamagedFilePastAnySongIsCutAndSaysSo() {
        let steps = Double(MelodyPattern.maxBars * MelodyPattern.stepsPerBar)
        let result = MelodyImport.pattern(from: [track("Lead", notes: [(60, 0, 1), (62, steps + 8, 1)])], sampleID: 1, bars: 1)
        #expect(result.pattern.bars == MelodyPattern.maxBars && result.pattern.tracks[0].notes.count == 1)
        #expect(result.notice?.contains("bars") == true, "says where the file was cut")
    }

    @Test func aFileWithoutNotesGivesAnEmptyMelodyAndSaysSo() {
        let result = MelodyImport.pattern(from: [], sampleID: 1, bars: 2)
        #expect(result.pattern.tracks.isEmpty && result.notice?.contains("no notes") == true)
    }
}

@Suite struct MidiFileNameTests {
    @Test func midiFilesAreRecognisedByTheirExtension() {
        for name in ["tune.mid", "Tune.MID", "tune.midi", "my song.Midi"] {
            #expect(MidiFile.isMidiFile(URL(fileURLWithPath: "/tmp/\(name)")), "\(name) is MIDI")
        }
        for name in ["tune.wav", "tune.mid.wav", "mid", "tune.mp3"] {
            #expect(!MidiFile.isMidiFile(URL(fileURLWithPath: "/tmp/\(name)")), "\(name) is not MIDI")
        }
    }
}

@Suite struct MidiLimitsTests {
    @Test func aFileThatIsTooLargeIsRefusedBeforeItIsRead() throws {
        let url = TestSupport.tempDir().appendingPathComponent("big.mid")
        try Midi.file(tracks: [Midi.event(0, 0x90, 60, 100) + Midi.event(480, 0x80, 60, 0) + Midi.endOfTrack]).write(to: url)
        #expect(throws: MidiError.tooLarge) { try MidiFile.read(url: url, maxBytes: 20) }
        #expect(try MidiFile.read(url: url).count == 1, "the normal limit is far above a real song")
        #expect(MidiError.tooLarge.errorDescription?.contains("too large") == true)
    }

    @Test func aFloodOfNotesIsAllKeptAndImportsQuickly() {
        let notes = (0..<50_000).map { i in
            MidiNote(pitch: i % 128, start: Double(i / 128) * 0.25, length: 0.25, velocity: 0.5)
        }
        let clock = ContinuousClock()
        var result: (pattern: MelodyPattern, notice: String?)?
        let took = clock.measure { result = MelodyImport.pattern(from: [MidiTrack(name: "Lots", notes: notes)], sampleID: 1, bars: 1) }
        #expect(result?.pattern.tracks[0].notes.count == 50_000, "no note is dropped for being one too many")
        #expect(result?.notice == nil)
        #expect(took < .seconds(3), "adding the notes does not slow down with each one")
    }
}
