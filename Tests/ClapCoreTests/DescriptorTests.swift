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

@Suite struct CategorizerTests {
    /// Fake text tower: each phrase is a one-hot-ish vector chosen by its first word.
    private static func fakeEmbed(_ text: String) -> [Float] {
        let axes = ["kick": 0, "snare": 1, "bass": 2, "tom": 3, "hat": 4]
        var v = [Float](repeating: 0.01, count: 5)
        for (word, axis) in axes where text.contains(word) { v[axis] = 1 }
        let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
        return v.map { $0 / n }
    }

    @Test func picksNearestCategoryAndAbstainsWhenUnsure() throws {
        let categorizer = try Categorizer(embed: { Self.fakeEmbed($0) }, categories: [
            ("Kick", ["a kick"]), ("Snare", ["a snare"]), ("Bass", ["a bass"]), ("Tom", ["a tom"]), ("Hat", ["a hat"]),
        ])
        let kickish = Self.fakeEmbed("kick"), snareish = Self.fakeEmbed("snare")
        let between: [Float] = {
            let v = [Float](repeating: 1, count: 5)
            let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot(); return v.map { $0 / n }
        }()
        let r = categorizer.classify(flat: kickish + snareish + between, count: 3)
        #expect(r[0].category == "Kick")
        #expect(r[1].category == "Snare")
        #expect(r[2].category == nil, "an equidistant sound is left uncategorised")
    }

    @Test func categoriesAreStoredAndCorrectable() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        _ = try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "a.wav", size: 1, mtime: 1)]) { _ in "f" }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: 1, sampleRate: 44100, channels: 1,
                                          embedding: Self.fakeEmbed("kick"), fingerprint: "f",
                                          modelVersion: ClapEmbedder.versionTag)])
        let categorizer = try Categorizer(embed: { Self.fakeEmbed($0) }, categories: [("Kick", ["a kick"]), ("Snare", ["a snare"])])
        #expect(store.categoryBacklog() == 1)
        try store.categorize(with: categorizer)
        #expect(store.categoryBacklog() == 0)
        #expect(store.loadSamples().first?.effectiveCategory == "Kick")

        try store.setManualCategory(sampleID: id, "Snare")
        #expect(store.loadSamples().first?.effectiveCategory == "Snare")
        try store.categorize(with: categorizer)    // recomputing must not touch the user's choice
        #expect(store.loadSamples().first?.effectiveCategory == "Snare")
        try store.setManualCategory(sampleID: id, nil)
        #expect(store.loadSamples().first?.effectiveCategory == "Kick")

        try store.setManualCategories([(id, "Snare")])             // the same for several samples at once
        #expect(store.loadSamples().first?.effectiveCategory == "Snare")
        try store.setManualCategories([(id, nil)])
        #expect(store.loadSamples().first?.effectiveCategory == "Kick")
    }
}

@Suite struct DuplicateFinderTests {
    private func unit(_ axis: Int, tilt: Float = 0) -> [Float] {
        var v = [Float](repeating: 0, count: 512)
        v[axis] = 1; v[(axis + 1) % 512] = tilt
        let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
        return v.map { $0 / n }
    }

    @Test func onlyFilesWithTheSameFingerprintAreGroupedAndTheUsedCopyIsFirst() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        let names = ["a.wav", "backup/a.wav", "deep/folder/a_remix.wav", "other.wav", "b.wav", "b copy.wav", "b again.wav"]
        let fingerprints = ["a.wav": "f1", "backup/a.wav": "f1", "deep/folder/a_remix.wav": "f2",
                            "other.wav": "f3", "b.wav": "f4", "b copy.wav": "f4", "b again.wav": "f4"]
        try store.sync(rootID: root.id, scanned: names.map { ScannedFile(relPath: $0, size: 10, mtime: 1) }) { fingerprints[$0] }
        // The remix sounds just like a.wav, but its bytes differ, so it must not be flagged.
        let vectors = ["a.wav": unit(0), "backup/a.wav": unit(0), "deep/folder/a_remix.wav": unit(0, tilt: 0.05),
                       "other.wav": unit(100), "b.wav": unit(200), "b copy.wav": unit(300), "b again.wav": unit(400)]
        for job in store.pendingJobs(limit: 20) {
            let rel = job.url.path.replacingOccurrences(of: "/tmp/x/", with: "")
            try store.save(results: [.success(id: job.id, duration: 1, sampleRate: 44100, channels: 1,
                                              embedding: vectors[rel]!, fingerprint: fingerprints[rel]!, modelVersion: "m")])
        }
        var samples = store.loadSamples()
        let used = try #require(samples.first { $0.relPath == "backup/a.wav" })
        try store.recordGrab(sampleID: used.id)       // the used copy should come first
        samples = store.loadSamples()
        func id(_ rel: String) -> Int64 { samples.first { $0.relPath == rel }!.id }

        let groups = DuplicateFinder.find(store: store, samples: samples)
        #expect(groups.count == 2, "one group per fingerprint shared by two or more files")
        #expect(groups.map(\.ids.count) == [3, 2], "the biggest group is listed first")
        #expect(Set(groups[0].ids) == [id("b.wav"), id("b copy.wav"), id("b again.wav")])
        #expect(Set(groups[1].ids) == [id("a.wav"), id("backup/a.wav")])
        #expect(groups[1].keeper == used.id, "the copy already in use is the one to keep")
        let flagged = Set(groups.flatMap(\.ids))
        #expect(!flagged.contains(id("deep/folder/a_remix.wav")), "a similar sound with different bytes is not a duplicate")
        #expect(!flagged.contains(id("other.wav")))
    }

    @Test func hiddenAndUnreadableFilesAreNeverFlagged() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        let names = ["a.wav", "a copy.wav", "a hidden.wav"]
        try store.sync(rootID: root.id, scanned: names.map { ScannedFile(relPath: $0, size: 10, mtime: 1) }) { _ in "same" }
        for job in store.pendingJobs(limit: 10) {
            try store.save(results: [.success(id: job.id, duration: 1, sampleRate: 44100, channels: 1,
                                              embedding: unit(0), fingerprint: "same", modelVersion: "m")])
        }
        let hidden = try #require(store.loadSamples().first { $0.relPath == "a hidden.wav" })
        try store.setHidden([hidden.id], true)

        let groups = DuplicateFinder.find(store: store, samples: store.loadSamples())
        #expect(groups.count == 1)
        #expect(!groups[0].ids.contains(hidden.id), "a copy the user already hid is not shown again")
    }

    @Test func hidingIsReversibleAndLeavesFinderAlone() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "a.wav", size: 1, mtime: 1)]) { _ in nil }
        let id = store.loadSamples()[0].id
        try store.setHidden([id], true)
        #expect(store.loadSamples()[0].hidden)
        try store.setHidden([id], false)
        #expect(!store.loadSamples()[0].hidden)
    }
}

@Suite struct ReuseInsightsTests {
    private func record(_ id: Int64, uses: Int, hidden: Bool = false) -> SampleRecord {
        var s = SampleRecord(id: id, rootID: 1, rootPath: "/", relPath: "s\(id).wav", name: "s\(id)", ext: "wav", duration: 1,
                             sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok, useCount: uses, lastUsed: nil, cueCount: 0)
        s.hidden = hidden
        return s
    }

    @Test func suggestsUnusedNeighboursOfHeavilyUsedSamples() {
        // 1 and 2 are close; 3 is close to 1; 4 is far away; 5 is close but hidden.
        let vectors: [[Float]] = [[1, 0, 0], [0.95, 0.31, 0], [0.9, 0, 0.43], [0, 1, 0], [0.99, 0.1, 0]]
        let flat = vectors.flatMap { v -> [Float] in let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot(); return v.map { $0 / n } }
        let index = VectorIndex(ids: [1, 2, 3, 4, 5], vectors: flat, dim: 3)
        let samples = [record(1, uses: 4), record(2, uses: 0), record(3, uses: 0), record(4, uses: 0), record(5, uses: 0, hidden: true)]
        let result = ReuseInsights.suggestions(samples: samples, index: index, perSample: 2)
        #expect(result.count == 1)
        #expect(result[0].favoriteID == 1 && result[0].uses == 4)
        #expect(result[0].alternatives.map(\.id) == [2, 3], "closest first, hidden skipped, far ones after")
    }

    @Test func usedNeighboursAreNotAlternatives() {
        let index = VectorIndex(ids: [1, 2], vectors: [1, 0, 1, 0], dim: 2)
        let result = ReuseInsights.suggestions(samples: [record(1, uses: 3), record(2, uses: 1)], index: index)
        #expect(result.filter { $0.favoriteID == 1 }.isEmpty, "everything similar was already used")
    }
}

@Suite struct TempoSyncTests {
    @Test func rateFoldsHalfAndDoubleTime() {
        #expect(TempoSync.rate(sampleBPM: 120, projectBPM: 120) == 1)
        #expect(abs(TempoSync.rate(sampleBPM: 100, projectBPM: 110) - 1.1) < 1e-5)
        #expect(abs(TempoSync.rate(sampleBPM: 70, projectBPM: 140) - 1) < 1e-5, "double time already fits")
        #expect(abs(TempoSync.rate(sampleBPM: 140, projectBPM: 72) - 1.0286) < 1e-3, "half time folds")
        #expect(TempoSync.rate(sampleBPM: nil, projectBPM: 120) == 1)
        #expect(TempoSync.rate(sampleBPM: 120, projectBPM: nil) == 1)
        #expect(TempoSync.rate(sampleBPM: 0, projectBPM: 120) == 1)
    }

    @Test func semitonesTakeTheShortWay() {
        #expect(TempoSync.semitones(sampleKey: "A1", projectTonic: "A") == 0)
        #expect(TempoSync.semitones(sampleKey: "C major", projectTonic: "D") == 2)
        #expect(TempoSync.semitones(sampleKey: "A minor", projectTonic: "C") == 3)
        #expect(TempoSync.semitones(sampleKey: "B1", projectTonic: "C") == 1, "wraps across the octave")
        #expect(TempoSync.semitones(sampleKey: "C", projectTonic: "B") == -1)
        #expect(TempoSync.semitones(sampleKey: nil, projectTonic: "C") == 0)
        #expect(TempoSync.semitones(sampleKey: "F#2", projectTonic: nil) == 0)
    }
}

@Suite struct LoudnessMatchTests {
    @Test func bringsSamplesToTheTargetWithinLimits() {
        #expect(LoudnessMatch.gainDB(loudnessDB: -30, peakDB: -20) == 12)         // boost
        #expect(LoudnessMatch.gainDB(loudnessDB: -8, peakDB: -0.5) == -10)        // cut
        #expect(LoudnessMatch.gainDB(loudnessDB: -60, peakDB: -50) == 18, "boost is capped")
        #expect(LoudnessMatch.gainDB(loudnessDB: -30, peakDB: -6) == 5, "peaks stay under the ceiling")
        #expect(LoudnessMatch.gainDB(loudnessDB: nil, peakDB: nil) == 0)
        #expect(LoudnessMatch.gainDB(loudnessDB: -120, peakDB: -120) == 0, "silence is left alone")
    }
}

@Suite struct AspectSimilarityTests {
    private func record(_ id: Int64, pitch: Double? = nil, centroid: Double = 2000, duration: Double = 1) -> SampleRecord {
        var s = SampleRecord(id: id, rootID: 1, rootPath: "/", relPath: "s\(id).wav", name: "s\(id)", ext: "wav", duration: duration,
                             sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        s.pitchHz = pitch; s.centroidHz = centroid; s.loudnessDB = -20; s.crestDB = 10
        return s
    }

    @Test func defaultWeightsAreSimpleSimilarity() {
        let index = VectorIndex(ids: [1, 2, 3], vectors: [1, 0, 0.9, 0.436, 0, 1], dim: 2)
        let ranked = AspectSimilarity.rank(reference: record(1), index: index, weights: AspectWeights(), limit: 2) { _ in nil }
        #expect(ranked.map { index.ids[$0.row] } == [2, 3])
    }

    @Test func pitchAspectPrefersTheSameNoteOverTheClosestTimbre() {
        // 2 sounds very alike (cosine .99) but a fourth apart; 3 is less alike (.7) but the same note an octave up.
        let index = VectorIndex(ids: [1, 2, 3], vectors: [1, 0, 0.99, 0.141, 0.7, 0.714], dim: 2)
        let samples: [Int64: SampleRecord] = [1: record(1, pitch: 220), 2: record(2, pitch: 293.66), 3: record(3, pitch: 440)]
        let plain = AspectSimilarity.rank(reference: samples[1]!, index: index, weights: AspectWeights(), limit: 2) { samples[$0] }
        #expect(index.ids[plain[0].row] == 2)
        let pitched = AspectSimilarity.rank(reference: samples[1]!, index: index, weights: AspectWeights(overall: 0.3, pitch: 1), limit: 2) { samples[$0] }
        #expect(index.ids[pitched[0].row] == 3, "octave-up match wins when pitch matters")
    }

    @Test func aspectsScoreInTheirOwnTerms() {
        #expect(AspectSimilarity.brightness(record(1, centroid: 1000), record(2, centroid: 1000)) == 1)
        #expect(AspectSimilarity.brightness(record(1, centroid: 1000), record(2, centroid: 4000)) == 0)
        #expect(AspectSimilarity.length(record(1, duration: 1), record(2, duration: 2)) > 0.6)
        #expect(AspectSimilarity.pitch(record(1, pitch: 100), record(2, pitch: nil)) == 0)
        #expect(AspectSimilarity.pitch(record(1, pitch: nil), record(2, pitch: 100)) == 0.5)
    }
}

@Suite struct KitBuilderTests {
    private func record(_ id: Int64, _ category: String, folder: String = "", loudness: Double = -20, loop: Bool? = false, hidden: Bool = false) -> SampleRecord {
        var s = SampleRecord(id: id, rootID: 1, rootPath: "/", relPath: folder.isEmpty ? "s\(id).wav" : "\(folder)/s\(id).wav",
                             name: "s\(id)", ext: "wav", duration: 1, sampleRate: 44100, channels: 1, size: 1, mtime: 0,
                             status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        s.category = category; s.loudnessDB = loudness; s.isLoop = loop; s.hidden = hidden
        return s
    }

    @Test func fillsSlotsWithTheBestFitAndKeepsTheAnchor() {
        // 1 kick (anchor); snares 2 (close), 3 (far), 4 (close but a loop), 5 (close but hidden); hat 6; no clap in the library.
        let vectors: [[Float]] = [[1, 0], [0.95, 0.31], [0.2, 0.98], [0.99, 0.14], [0.99, 0.14], [0.8, 0.6]]
        let flat = vectors.flatMap { v -> [Float] in let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot(); return v.map { $0 / n } }
        let index = VectorIndex(ids: [1, 2, 3, 4, 5, 6], vectors: flat, dim: 2)
        let samples = [record(1, "Kick"), record(2, "Snare"), record(3, "Snare"), record(4, "Snare", loop: true),
                       record(5, "Snare", hidden: true), record(6, "Hi-hat")]
        let kit = KitBuilder.suggest(anchor: samples[0], samples: samples, index: index)
        #expect(kit.map(\.category) == ["Kick", "Snare", "Hi-hat"], "empty categories are skipped")
        #expect(kit[0].isAnchor && kit[0].candidates == [1])
        #expect(kit[1].candidates == [2, 3], "loops and hidden samples never suggested, nearer first")
    }

    @Test func packAndLevelBreakTies() {
        let vectors: [[Float]] = [[1, 0], [0.9, 0.436], [0.9, 0.436], [0.9, 0.436]]
        let flat = vectors.flatMap { v -> [Float] in let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot(); return v.map { $0 / n } }
        let index = VectorIndex(ids: [1, 2, 3, 4], vectors: flat, dim: 2)
        let samples = [record(1, "Kick", folder: "PackA"), record(2, "Snare", folder: "PackB", loudness: -20),
                       record(3, "Snare", folder: "PackA", loudness: -20), record(4, "Snare", folder: "PackB", loudness: -40)]
        let kit = KitBuilder.suggest(anchor: samples[0], samples: samples, index: index)
        #expect(kit[1].candidates == [3, 2, 4], "same pack first, then matching level")
    }

    @Test func uncategorisedAnchorStillAppears() {
        let index = VectorIndex(ids: [1], vectors: [1, 0], dim: 2)
        var s = record(1, "Kick"); s.category = nil
        let kit = KitBuilder.suggest(anchor: s, samples: [s], index: index)
        #expect(kit.count == 1 && kit[0].isAnchor)
    }
}
