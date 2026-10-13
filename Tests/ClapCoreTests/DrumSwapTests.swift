import Foundation
import Testing
@testable import ClapCore

private struct FixedGenerator: RandomNumberGenerator {
    var value: UInt64
    mutating func next() -> UInt64 { value }
}

@Suite struct DrumSwapTests {
    private func record(_ id: Int64, _ category: String?, loop: Bool? = false, hidden: Bool = false, duration: Double = 1) -> SampleRecord {
        var s = SampleRecord(id: id, rootID: 1, rootPath: "/", relPath: "s\(id).wav", name: "s\(id)", ext: "wav", duration: duration,
                             sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        s.category = category; s.isLoop = loop; s.hidden = hidden
        return s
    }

    /// Kicks 1...4 get steadily further from kick 1; a snare sits right next to it.
    private func fixture() -> (samples: [SampleRecord], index: VectorIndex) {
        let samples = [record(1, "Kick"), record(2, "Kick"), record(3, "Kick"), record(4, "Kick"),
                       record(5, "Snare"), record(6, "Kick", loop: true), record(7, "Kick", hidden: true)]
        let angles: [Int64: Double] = [1: 0, 2: 0.1, 3: 0.3, 4: 0.6, 5: 0.05, 6: 0.02, 7: 0.01]
        var vectors: [Float] = []
        for s in samples { let a = angles[s.id]!; vectors += [Float(cos(a)), Float(sin(a))] }
        return (samples, VectorIndex(ids: samples.map(\.id), vectors: vectors, dim: 2))
    }

    @Test func candidatesFillTheSameRoleNearestFirst() {
        let (samples, index) = fixture()
        let byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        let found = DrumSwap.candidates(for: byID[1]!, index: index, samples: samples, lookup: { byID[$0] }, excluding: [])
        #expect(found == [2, 3, 4], "same category, one-shots only, not hidden, closest first: \(found)")
    }

    @Test func soundsAlreadyInTheKitAreLeftOut() {
        let (samples, index) = fixture()
        let byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        let found = DrumSwap.candidates(for: byID[1]!, index: index, samples: samples, lookup: { byID[$0] }, excluding: [2])
        #expect(found == [3, 4])
    }

    @Test func withoutAnIndexAnyFittingSoundWillDo() {
        let (samples, _) = fixture()
        let byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        let found = DrumSwap.candidates(for: byID[1]!, index: nil, samples: samples, lookup: { byID[$0] }, excluding: [])
        #expect(found == [2, 3, 4])
    }

    @Test func variationLimitsHowFarAPickReaches() {
        var low = FixedGenerator(value: 0), high = FixedGenerator(value: .max)
        let candidates: [Int64] = [10, 20, 30, 40, 50]
        #expect(DrumSwap.pick(from: candidates, spread: 2, using: &low) == 10)
        #expect(DrumSwap.pick(from: candidates, spread: 2, using: &high) == 20, "never beyond the first two")
        #expect(DrumSwap.pick(from: [], spread: 4, using: &low) == nil)
        #expect(DrumVariation.close.spread < DrumVariation.medium.spread && DrumVariation.medium.spread < DrumVariation.wide.spread)
    }

    @Test func repeatedSwapsSkipWhatTheTrackHad() {
        let (samples, index) = fixture()
        let byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        var generator = FixedGenerator(value: 0)
        let next = DrumSwap.next(for: byID[1]!, history: [2], spread: 1, index: index, samples: samples,
                                 lookup: { byID[$0] }, excluding: [], using: &generator)
        #expect(next == 3, "2 was the previous sound")
        // Once the history has used everything up, an old sound is better than no swap.
        let again = DrumSwap.next(for: byID[1]!, history: [2, 3, 4], spread: 1, index: index, samples: samples,
                                  lookup: { byID[$0] }, excluding: [], using: &generator)
        #expect(again == 2)
    }

    @Test func swapsAreRememberedAndCanBeTakenBack() {
        var pattern = DrumPattern()
        pattern.addTrack(sampleID: 1, label: "Kick", category: "Kick")
        pattern.replaceSample(track: 0, with: 2)
        pattern.replaceSample(track: 0, with: 2)           // the same sound again is not a swap
        pattern.replaceSample(track: 0, with: 3)
        #expect(pattern.tracks[0].history == [1, 2])
        #expect(pattern.restorePreviousSample(track: 0) == 2 && pattern.tracks[0].sampleID == 2)
        #expect(pattern.restorePreviousSample(track: 0) == 1 && pattern.restorePreviousSample(track: 0) == nil)
        for n in 0..<50 { pattern.replaceSample(track: 0, with: Int64(100 + n)) }
        #expect(pattern.tracks[0].history.count == DrumTrack.historyLimit)
    }

    @Test func patternsSavedBeforeLocksStillLoad() throws {
        let old = #"{"swing":0,"tracks":[{"id":"6A2F8E58-0E0B-4F0E-9A57-1B2B0C6E1A11","sampleID":4,"label":"Kick","hits":[true,false],"volume":0.9,"muted":false,"solo":false,"alternatives":[1,2]}]}"#
        let pattern = try JSONDecoder().decode(DrumPattern.self, from: Data(old.utf8))
        #expect(pattern.tracks[0].sampleID == 4 && !pattern.tracks[0].locked && pattern.tracks[0].history.isEmpty)
        var locked = pattern
        locked.tracks[0].locked = true
        let round = try JSONDecoder().decode(DrumPattern.self, from: JSONEncoder().encode(locked))
        #expect(round.tracks[0].locked)
    }
}
