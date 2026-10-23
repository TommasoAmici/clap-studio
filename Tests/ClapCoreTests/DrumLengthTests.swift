import Foundation
import Testing
@testable import ClapCore

@Suite struct DrumLengthTests {
    @Test func changingLengthKeepsEarlierHitsAndPadsNewBarsWithSilence() throws {
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "Kick", category: "Kick", starter: false)
        pattern.toggle(track: 0, step: 3)
        pattern.setBars(3)
        pattern.toggle(track: 0, step: 47)
        #expect(pattern.totalSteps == 48 && pattern.tracks[0].hits.count == 48)
        #expect(pattern.tracks[0].hits.indices.filter { pattern.tracks[0].hits[$0] } == [3, 47])
        let saved = try JSONDecoder().decode(DrumPattern.self, from: JSONEncoder().encode(pattern))
        #expect(saved.sanitized() == pattern, "all bars survive relaunch")
        let file = TestSupport.tempDir().appendingPathComponent("drums.json")
        try DrumStore.save(pattern, to: file)
        #expect(DrumStore.load(from: file) == pattern)
        pattern.setBars(1)
        #expect(pattern.tracks[0].hits.count == 16 && pattern.tracks[0].hits[3])
        pattern.clearHits()
        #expect(!pattern.tracks[0].hits.contains(true))
    }

    @Test func oldPatternsStillHaveOneBarAndNewTracksRepeatTheirStarter() throws {
        let legacy = Data(#"{"tracks":[],"swing":0.2}"#.utf8)
        let old = try JSONDecoder().decode(DrumPattern.self, from: legacy)
        #expect(old.bars == 1)
        var pattern = DrumPattern(bars: 3)
        pattern.addTrack(sampleID: 1, label: "Kick", category: "Kick")
        #expect(pattern.tracks[0].hits.count == 48)
        #expect(pattern.tracks[0].hits[0] && pattern.tracks[0].hits[16] && pattern.tracks[0].hits[32])
        pattern.apply(DrumPreset.all[0])
        #expect(pattern.tracks[0].hits.count == 48, "grooves fill every bar")
        #expect(pattern.sanitized() == pattern)
        pattern.setBars(Int.max)
        #expect(pattern.bars == DrumPattern.maxBars, "damaged lengths cannot allocate without limit")
    }

    @Test func drumsAndMelodyLoopIndependentlyWhenLengthsDoNotDivide() {
        var drums = DrumPattern(bars: 3)
        drums.addTrack(sampleID: 1, label: "Kick", category: "Kick", starter: false)
        drums.toggle(track: 0, step: 40)
        var melody = MelodyPattern(bars: 2)
        melody.addTrack(sampleID: 2, label: "Bass")
        melody.addNote(track: 0, pitch: 48, start: 20, length: 1)
        var sequencer = DrumSequencer(startTime: 0)
        let events = sequencer.advance(now: 0, lookahead: 12, bpm: 120, pattern: drums, melody: melody)
        #expect(events.count == 96)
        #expect(events.enumerated().filter { !$0.element.tracks.isEmpty }.map(\.offset) == [40, 88],
                "the three-bar drum part starts again after 48 steps")
        #expect(events.enumerated().filter { !$0.element.notes.isEmpty }.map(\.offset) == [20, 52, 84],
                "the two-bar melody starts again after 32 steps")
        #expect(events[48].step == 0 && events[48].melodyStep == 16)
    }
}
