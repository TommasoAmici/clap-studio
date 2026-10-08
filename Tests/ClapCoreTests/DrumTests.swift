import Foundation
import Testing
@testable import ClapCore

@Suite struct DrumTests {
    @Test func stepTimingFollowsTempoAndSwing() {
        #expect(abs(DrumTiming.stepDuration(bpm: 120) - 0.125) < 1e-9)
        #expect(abs(DrumTiming.offset(ofStep: 4, bpm: 120, swing: 0) - 0.5) < 1e-9, "a beat is four steps")
        #expect(abs(DrumTiming.offset(ofStep: 1, bpm: 120, swing: 0.4) - 0.175) < 1e-9, "odd steps are late")
        #expect(abs(DrumTiming.offset(ofStep: 2, bpm: 120, swing: 0.4) - 0.25) < 1e-9, "even steps stay on the grid")
        // Swing gives long-short pairs that still add up to two plain steps.
        let pair = DrumTiming.interval(afterStep: 0, bpm: 100, swing: 0.3) + DrumTiming.interval(afterStep: 1, bpm: 100, swing: 0.3)
        #expect(abs(pair - 2 * DrumTiming.stepDuration(bpm: 100)) < 1e-9)
    }

    @Test func starterPatternsFitTheirRoles() {
        let kick = DrumStarter.hits(for: "Kick"), snare = DrumStarter.hits(for: "Snare")
        #expect(kick.count == 16 && kick.indices.filter { kick[$0] } == [0, 4, 8, 12])
        #expect(snare.indices.filter { snare[$0] } == [4, 12])
        #expect(!DrumStarter.hits(for: "Bass").contains(true) && !DrumStarter.hits(for: nil).contains(true))
    }

    @Test func editingAPattern() {
        var p = DrumPattern()
        for i in 0..<DrumPattern.maxTracks {
            let added = p.addTrack(sampleID: Int64(i), label: "t\(i)", category: "Kick")
            #expect(added)
        }
        let overflow = p.addTrack(sampleID: 99, label: "extra", category: nil)
        #expect(!overflow, "full")
        p.toggle(track: 0, step: 1)
        #expect(p.tracks[0].hits[1])
        p.toggle(track: 0, step: 1)
        #expect(!p.tracks[0].hits[1])
        p.toggle(track: 40, step: 1); p.toggle(track: 0, step: 40)           // out of range: ignored
        p.replaceSample(track: 2, with: 77)
        #expect(p.tracks[2].sampleID == 77 && p.tracks[2].hits == DrumStarter.hits(for: "Kick"), "swap keeps the rhythm")
        p.clearHits()
        #expect(!p.tracks.contains { $0.hits.contains(true) })
        p.removeTrack(at: 0)
        #expect(p.tracks.count == DrumPattern.maxTracks - 1)
    }

    @Test func sequencerSchedulesAheadAndLoops() {
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "k", category: "Kick")
        pattern.addTrack(sampleID: 2, label: "s", category: "Snare")
        var seq = DrumSequencer(startTime: 10)
        let first = seq.advance(now: 10, lookahead: 0.3, bpm: 120, pattern: pattern)
        #expect(first.map(\.step) == [0, 1, 2], "0.125 s steps inside 0.3 s")
        #expect(first[0].tracks == [0] && first[1].tracks.isEmpty)
        #expect(abs(first[2].time - 10.25) < 1e-9)
        // Nothing new until the clock moves.
        #expect(seq.advance(now: 10, lookahead: 0.3, bpm: 120, pattern: pattern).isEmpty)
        // Run through a whole bar: step 4 has kick, step 12 has kick and snare, then it wraps.
        var all = first
        var now = 10.0
        while all.count < 33 { now += 0.1; all += seq.advance(now: now, lookahead: 0.3, bpm: 120, pattern: pattern) }
        #expect(all[4].step == 4 && all[4].tracks == [0, 1], "kick and snare on beat two")
        #expect(all[12].step == 12 && all[12].tracks == [0, 1])
        #expect(all[16].step == 0 && all[16].tracks == [0], "wraps to the start of the bar")
        #expect(abs(all[16].time - 12.0) < 1e-9, "a bar is two seconds at 120 BPM")
    }

    @Test func muteAndSoloAndLiveTempo() {
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "k", category: "Kick")
        pattern.addTrack(sampleID: 2, label: "h", category: "Hi-hat")
        pattern.tracks[1].muted = true
        var seq = DrumSequencer(startTime: 0)
        #expect(seq.advance(now: 0, lookahead: 0.01, bpm: 120, pattern: pattern)[0].tracks == [0], "muted track is silent")
        pattern.tracks[1].muted = false
        pattern.tracks[1].solo = true
        let soloed = seq.advance(now: 0.5, lookahead: 0.01, bpm: 120, pattern: pattern)
        #expect(soloed.allSatisfy { !$0.tracks.contains(0) }, "solo silences the others")
        // Doubling the tempo halves the spacing from the next step on.
        let before = seq.nextTime
        _ = seq.advance(now: before, lookahead: 0.01, bpm: 240, pattern: pattern)
        #expect(abs(seq.nextTime - (before + 0.0625)) < 1e-9)
    }

    @Test func aStallResumesInsteadOfRacing() {
        var seq = DrumSequencer(startTime: 0)
        let events = seq.advance(now: 100, lookahead: 0.1, bpm: 120, pattern: DrumPattern())
        #expect(events.count <= 2 && (events.first?.time ?? 100) >= 100)
    }
}

@Suite struct SwingDisplayTests {
    @Test func percentIsCenteredOnStraight() {
        #expect(DrumTiming.swingPercent(0) == 50)
        #expect(abs(DrumTiming.swingPercent(1.0 / 3) - 66.667) < 0.01, "triplet feel")
        #expect(DrumTiming.swing(percent: 75) == 0.5 && DrumTiming.swing(percent: 25) == -0.5)
        #expect(DrumTiming.swing(percent: DrumTiming.swingPercent(0.2)) == 0.2)
    }

    @Test func earlySwingPullsOddStepsForward() {
        #expect(DrumTiming.offset(ofStep: 1, bpm: 120, swing: -0.4) < DrumTiming.stepDuration(bpm: 120))
    }
}

@Suite struct DrumMachineTests {
    private final class Steps: @unchecked Sendable {
        private let lock = NSLock(); private var list: [Int] = []
        func add(_ s: Int) { lock.lock(); list.append(s); lock.unlock() }
        var values: [Int] { lock.lock(); defer { lock.unlock() }; return list }
    }

    /// Needs an audio output; passes without checking anything when the engine cannot start (for example on a headless runner).
    @Test func runsInTimeAndStopsCleanly() async throws {
        let dir = TestSupport.tempDir()
        let url = dir.appendingPathComponent("hit.wav")
        try writeTestWav(url, seconds: 0.1) { Float(sin(2 * .pi * 200 * $0)) * 0.3 }
        let machine = DrumMachine(cache: AudioBufferCache(sampleRate: 48_000))
        let steps = Steps()
        machine.onStep = { steps.add($0) }
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "kick", category: "Kick")
        machine.update(pattern: pattern, urls: [1: url])
        machine.bpm = 240                                    // 62.5 ms per step
        machine.start()
        try await Task.sleep(for: .milliseconds(300))
        guard machine.isRunning else { return }
        try await Task.sleep(for: .milliseconds(1000))
        machine.stop()
        try await Task.sleep(for: .milliseconds(300))
        let seen = steps.values
        #expect(seen.count >= 10, "about 20 steps in 1.3 s at 240 BPM, got \(seen.count)")
        #expect(zip(seen, seen.dropFirst()).allSatisfy { ($0 + 1) % 16 == $1 }, "steps arrive in order")
        #expect(!machine.isRunning)
        let before = steps.values.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(steps.values.count == before, "nothing plays after stop")
    }
}
