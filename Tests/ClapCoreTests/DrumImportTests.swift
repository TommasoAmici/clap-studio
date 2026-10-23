import Foundation
import Testing
@testable import ClapCore

@Suite struct DrumImportTests {
    @Test func eachMidiTrackBecomesARowAndStartsSnapToSixteenths() {
        let tracks = [
            MidiTrack(name: "Kick", notes: [
                MidiNote(pitch: 36, start: 0.2, length: 1, velocity: 1),
                MidiNote(pitch: 40, start: 0.4, length: 1, velocity: 0.5),
                MidiNote(pitch: 36, start: 35.7, length: 0.25, velocity: 1),
            ]),
            MidiTrack(name: "  ", notes: [MidiNote(pitch: 42, start: 4.6, length: 1, velocity: 1)]),
        ]
        let imported = DrumImport.pattern(from: tracks, selectedSampleID: 7)
        let pattern = imported.pattern
        #expect(pattern.bars == 3 && pattern.tracks.count == 2)
        #expect(pattern.tracks.map(\.label) == ["Kick", "Track 2"])
        #expect(pattern.tracks.map(\.sampleID) == [7, 7])
        #expect(pattern.tracks[0].hits.indices.filter { pattern.tracks[0].hits[$0] } == [0, 36],
                "pitches are ignored and notes snapped to the same step become one hit")
        #expect(pattern.tracks[1].hits.indices.filter { pattern.tracks[1].hits[$0] } == [5])
        #expect(imported.notice == nil)
    }

    @Test func existingSoundsAreReusedAndExtraRowsCanWaitForASound() {
        var old = DrumPattern(swing: 0.2, bars: 8)
        old.addTrack(sampleID: 11, label: "Old", category: "Kick")
        let tracks = (0..<2).map {
            MidiTrack(name: "Part \($0)", notes: [MidiNote(pitch: 36, start: 0, length: 1, velocity: 1)])
        }
        let imported = DrumImport.pattern(from: tracks, existing: old, selectedSampleID: nil).pattern
        #expect(imported.tracks.map(\.sampleID) == [11, DrumTrack.unassignedSampleID])
        #expect(imported.bars == 1 && imported.swing == 0.2, "the new song replaces the old length but keeps the swing")
        #expect(imported.tracks[0].hits.filter { $0 }.count == 1, "old steps are replaced")
    }

    @Test func extraTracksAndDamagedPositionsAreReported() {
        let tracks = (0..<10).map {
            MidiTrack(name: "\($0)", notes: [
                MidiNote(pitch: 36, start: 0, length: 1, velocity: 1),
                MidiNote(pitch: 36, start: .infinity, length: 1, velocity: 1),
                MidiNote(pitch: 36, start: -1, length: 1, velocity: 1),
                MidiNote(pitch: 36, start: Double(DrumPattern.maxBars * 16), length: 1, velocity: 1),
            ])
        }
        let imported = DrumImport.pattern(from: tracks, selectedSampleID: 1)
        #expect(imported.pattern.tracks.count == 8 && imported.pattern.bars == 1)
        #expect(imported.notice?.contains("8 of 10") == true)
        #expect(imported.notice?.contains("left out") == true)
        #expect(imported.pattern.tracks.allSatisfy { $0.hits.filter { $0 }.count == 1 })
    }

    @Test func formatZeroKeepsItsPhysicalTrackForDrums() throws {
        let body = Midi.name("Combined drums")
            + Midi.event(0, 0x99, 36, 100) + Midi.event(0, 0x91, 40, 100)
            + Midi.event(120, 0x89, 36, 0) + Midi.event(0, 0x81, 40, 0) + Midi.endOfTrack
        let song = try MidiFile.parseSong(Midi.file(format: 0, tracks: [body]), splitChannels: false)
        #expect(song.tracks.count == 1 && song.tracks[0].notes.count == 2,
                "drum rows follow the file's tracks, including tracks with several channels")
        #expect(song.tracks[0].name == "Combined drums")
    }
}
