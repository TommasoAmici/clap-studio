import Foundation
import Testing
@testable import ClapCore

@Suite struct DescriptorTests {
    static let sr = 32_000.0

    func render(seconds: Double, _ f: (Double) -> Double) -> [Float] {
        (0..<Int(seconds * Self.sr)).map { Float(f(Double($0) / Self.sr)) }
    }

    func analyze(_ x: [Float], fileDuration: Double? = nil) -> SoundDescriptors {
        DescriptorAnalyzer().analyze(samples: x, sampleRate: Self.sr, fileDuration: fileDuration ?? Double(x.count) / Self.sr)
    }

    /// Four-on-the-floor kick pattern with off-beat hats at `bpm`.
    func drumLoop(bpm: Double, bars: Int) -> [Float] {
        let beat = 60 / bpm, seconds = beat * 4 * Double(bars)
        var rng = SplitMix64(seed: 3)
        let noise = (0..<Int(seconds * Self.sr) + 100).map { _ in rng.nextFloat() * 2 - 1 }
        return render(seconds: seconds) { t in
            let sinceBeat = t.truncatingRemainder(dividingBy: beat)
            let kick = sin(2 * .pi * (55 + 90 * exp(-sinceBeat * 30)) * sinceBeat) * exp(-sinceBeat * 9)
            let sinceOff = (t + beat / 2).truncatingRemainder(dividingBy: beat)
            let hat = Double(noise[Int(t * Self.sr)]) * exp(-sinceOff * 60) * 0.25
            return 0.8 * kick + hat
        }
    }

    @Test func levelsMatchTheMath() {
        let d = analyze(render(seconds: 1) { 0.5 * sin(2 * .pi * 440 * $0) })
        #expect(abs(d.peakDB - (-6.02)) < 0.1)
        #expect(abs(d.loudnessDB - (-9.03)) < 0.2, "RMS of a 0.5 sine is -9.03 dBFS")
        #expect(abs(d.crestDB - 3.01) < 0.3, "a sine's crest factor is 3 dB")
    }

    @Test func silenceIsHandled() {
        let d = analyze([Float](repeating: 0, count: 32_000))
        #expect(d.loudnessDB == -120 && !d.isLoop && d.bpm == nil)
    }

    @Test func brightnessFollowsFrequencyContent() {
        let dark = analyze(render(seconds: 1) { 0.5 * sin(2 * .pi * 200 * $0) })
        let bright = analyze(render(seconds: 1) { 0.5 * sin(2 * .pi * 6000 * $0) })
        #expect(abs(dark.centroidHz - 200) < 60)
        #expect(abs(bright.centroidHz - 6000) < 300)
    }

    @Test func punchySoundsHaveHigherCrestThanSustained() {
        let kick = analyze(render(seconds: 1) { sin(2 * .pi * 60 * $0) * exp(-$0 * 12) })
        let pad = analyze(render(seconds: 1) { 0.5 * sin(2 * .pi * 220 * $0) })
        #expect(kick.crestDB > pad.crestDB + 2)
    }

    @Test func pitchOfATonalOneShot() throws {
        for (hz, note) in [(440.0, "A4"), (55.0, "A1"), (261.63, "C4")] {
            let d = analyze(render(seconds: 1) { 0.6 * sin(2 * .pi * hz * $0) * exp(-$0 * 2) })
            let found = try #require(d.pitchHz, "\(hz) Hz")
            #expect(abs(found - hz) / hz < 0.01, "\(hz) Hz -> \(found)")
            #expect(d.keyName == note)
            #expect(!d.isLoop)
        }
    }

    @Test func noiseHasNoPitch() {
        var rng = SplitMix64(seed: 1)
        let d = analyze(render(seconds: 0.5) { _ in Double(rng.nextFloat() * 2 - 1) * 0.5 })
        #expect(d.pitchHz == nil && d.keyName == nil)
    }

    @Test func loopTempoIsDetected() throws {
        for bpm in [90.0, 120.0, 140.0] {
            let d = analyze(drumLoop(bpm: bpm, bars: 2))
            #expect(d.isLoop, "\(bpm) BPM loop")
            let found = try #require(d.bpm)
            #expect(abs(found - bpm) / bpm < 0.02, "\(bpm) -> \(found)")
        }
    }

    @Test func aSingleHitIsNotALoop() {
        let d = analyze(render(seconds: 2) { sin(2 * .pi * 60 * $0) * exp(-$0 * 8) })
        #expect(!d.isLoop && d.bpm == nil)
    }

    @Test func loopKeyFromChords() {
        // A minor triad (A C E) pulsed at 100 BPM so it counts as a loop.
        let beat = 0.6
        let x = render(seconds: beat * 8) { t in
            let env = exp(-t.truncatingRemainder(dividingBy: beat) * 6)
            return 0.3 * env * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 261.63 * t) + sin(2 * .pi * 329.63 * t))
        }
        let d = analyze(x)
        #expect(d.isLoop)
        #expect(d.keyName == "A minor", "got \(d.keyName ?? "nil")")
    }

    @Test func noteNames() {
        #expect(NoteNames.name(forHz: 440) == "A4")
        #expect(NoteNames.name(forHz: 27.5) == "A0")
        #expect(NoteNames.name(forHz: 5) == nil)
    }
}

@Suite struct DescriptorFilterTests {
    private func sample(loop: Bool?, bpm: Double? = nil, manual: Double? = nil, key: String? = nil) -> SampleRecord {
        SampleRecord(id: 1, rootID: 1, rootPath: "/", relPath: "a.wav", name: "a", ext: "wav", duration: 1, sampleRate: 44100,
                     channels: 1, size: 1, mtime: 0, status: .ok, useCount: 0, lastUsed: nil, cueCount: 0,
                     isLoop: loop, bpm: bpm, bpmManual: manual, keyName: key)
    }

    @Test func kindAndTempo() {
        var f = DescriptorFilter()
        #expect(!f.isActive)
        f.kind = .loop
        #expect(f.matches(sample(loop: true)) && !f.matches(sample(loop: false)) && !f.matches(sample(loop: nil)))
        f.kind = .oneShot
        #expect(f.matches(sample(loop: false)) && f.matches(sample(loop: nil)) && !f.matches(sample(loop: true)))

        f = DescriptorFilter(); f.bpmMin = 100; f.bpmMax = 130
        #expect(f.matches(sample(loop: true, bpm: 120)))
        #expect(!f.matches(sample(loop: true, bpm: 140)))
        #expect(f.matches(sample(loop: true, bpm: 140, manual: 110)), "the user's value wins")
        #expect(!f.matches(sample(loop: false)), "no tempo, no match")
    }

    @Test func tonicMatchesNotesAndKeys() {
        var f = DescriptorFilter(); f.tonic = "A"
        #expect(f.matches(sample(loop: false, key: "A1")))
        #expect(f.matches(sample(loop: true, key: "A minor")))
        #expect(!f.matches(sample(loop: false, key: "A#1")), "A# is a different tonic")
        #expect(!f.matches(sample(loop: false, key: nil)))
        f.tonic = "C#"
        #expect(f.matches(sample(loop: true, key: "C# major")))
        #expect(DescriptorFilter.tonic(of: "G minor") == "G")
    }
}
