import Foundation
import Testing
@testable import ClapCore

@Suite struct MelodyTimingTests {
    private func melody(bars: Int = 1, _ notes: [(pitch: Int, start: Double, length: Double)] = []) -> MelodyPattern {
        var m = MelodyPattern()
        m.addTrack(sampleID: 1, label: "Pad")
        m.setBars(bars)
        for n in notes { m.addNote(track: 0, pitch: n.pitch, start: n.start, length: n.length) }
        return m
    }

    /// Runs the sequencer for `steps` steps at 120 BPM (0.125 s each) and gathers every event.
    private func run(steps: Int, drums: DrumPattern = DrumPattern(), melody: MelodyPattern) -> [DrumEvent] {
        var seq = DrumSequencer(startTime: 0)
        var all: [DrumEvent] = []
        var now = 0.0
        while all.count < steps { all += seq.advance(now: now, lookahead: 0.3, bpm: 120, pattern: drums, melody: melody); now += 0.1 }
        return Array(all.prefix(steps))
    }

    @Test func notesStartOnTheSameClockAsTheDrums() throws {
        var drums = DrumPattern()
        drums.addTrack(sampleID: 5, label: "k", category: "Kick")
        let events = run(steps: 16, drums: drums, melody: melody([(60, 4, 2)]))
        let hit = try #require(events[4].notes.first)
        #expect(events[4].tracks == [0], "the kick on beat two and the note start together")
        #expect(hit.track == 0 && hit.pitch == 60 && abs(hit.time - events[4].time) < 1e-9 && abs(hit.time - 0.5) < 1e-9)
        #expect(abs(hit.duration - 0.25) < 1e-9, "two steps of 0.125 s")
        #expect(events.enumerated().allSatisfy { $0.offset == 4 || $0.element.notes.isEmpty }, "no other step has a note")
    }

    @Test func notesBetweenStepsAndSwingFollowTheDrumGroove() throws {
        var drums = DrumPattern()
        drums.swing = 0.4
        let events = run(steps: 8, drums: drums, melody: melody([(62, 2.5, 1)]))
        let hit = try #require(events[2].notes.first, "a note at 2.5 begins during step 2")
        // Step 2 starts at 0.25 s and, with this swing, lasts 0.175 s: the note starts half way through it.
        #expect(abs(hit.time - 0.3375) < 1e-9)
        // It ends half way through step 3, which starts at 0.425 s and lasts 0.075 s: 0.4625 s.
        #expect(abs(hit.time + hit.duration - 0.4625) < 1e-9, "its end is on the swung grid too")
    }

    @Test func aLongerPatternLoopsOnItsOwnLengthWhileTheDrumsKeepTheirBar() {
        let events = run(steps: 70, melody: melody(bars: 2, [(60, 20, 1)]))
        #expect(events[20].notes.count == 1 && events[52].notes.count == 1 && events[21].notes.isEmpty)
        #expect(abs(events[52].time - 6.5) < 1e-9, "the second time round, one 32-step loop later")
        #expect(events[16].step == 0 && events[32].step == 0, "the drums still loop every bar")
        #expect(events[20].melodyStep == 20 && events[32].melodyStep == 0 && events[52].melodyStep == 20, "the playhead wraps at the pattern end")
    }

    @Test func mutedTracksAreSilentAndSoloIsSharedWithTheDrums() {
        var m = melody([(60, 0, 1)])
        m.tracks[0].muted = true
        #expect(run(steps: 4, melody: m)[0].notes.isEmpty)

        m.tracks[0].muted = false
        var drums = DrumPattern()
        drums.addTrack(sampleID: 5, label: "k", category: "Kick")
        drums.tracks[0].solo = true
        let drumSolo = run(steps: 4, drums: drums, melody: m)[0]
        #expect(drumSolo.tracks == [0] && drumSolo.notes.isEmpty, "soloing a drum track silences the melody")

        drums.tracks[0].solo = false
        m.tracks[0].solo = true
        let melodySolo = run(steps: 4, drums: drums, melody: m)[0]
        #expect(melodySolo.tracks.isEmpty && melodySolo.notes.count == 1, "soloing a melody track silences the drums")
    }

    @Test func notesGetTheirTrackAndVelocity() throws {
        var m = melody()
        m.addTrack(sampleID: 2, label: "Bass")
        m.addNote(track: 1, pitch: 36, start: 0, length: 2, velocity: 0.25)
        m.addNote(track: 0, pitch: 72, start: 0, length: 2, velocity: 1)
        let hits = run(steps: 1, melody: m)[0].notes
        #expect(hits.map(\.track).sorted() == [0, 1])
        #expect(hits.first { $0.track == 1 }?.velocity == 0.25 && hits.first { $0.track == 1 }?.pitch == 36)
    }
}
