import Foundation
import Testing
@testable import ClapCore

@Suite struct FieldRecordingTests {
    @Test func regularSampleChoiceSurvivesReindexingAndCanBeUndone() async throws {
        let dir = TestSupport.tempDir()
        try writeTestWav(dir.appendingPathComponent("long.wav"), seconds: 31) {
            Float(sin(2 * .pi * 440 * $0)) * 0.3
        }
        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        let pipeline = IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1)
        _ = await pipeline.run(onProgress: { _ in })
        let id = try #require(store.loadSamples().first).id
        try store.setManualCategory(sampleID: id, FieldRecording.categoryName)
        try store.setRegularSamples([(id: id, regular: true, category: nil)])
        #expect(store.sample(id: id)?.isFieldRecording == false, "the explicit choice wins over length")
        #expect(store.pendingCount() == 1, "the sound must be read again as a single sample")
        _ = await pipeline.run(onProgress: { _ in })
        #expect(store.segmentCount(sampleID: id) == 0)
        #expect(try store.markFieldRecordingsStale() == 0, "rescanning keeps the choice")
        let reopened = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        #expect(reopened.sample(id: id)?.isRegularSample == true, "the choice survives relaunch")
        try store.setRegularSamples([(id: id, regular: false, category: FieldRecording.categoryName)])
        _ = await pipeline.run(onProgress: { _ in })
        #expect(store.sample(id: id)?.isFieldRecording == true)
        #expect(store.segmentCount(sampleID: id) > 0, "undo restores segmented processing")
    }

    @Test func thresholdIsThirtySeconds() {
        #expect(!FieldRecording.isFieldRecording(duration: 29.9))
        #expect(FieldRecording.isFieldRecording(duration: 30))
    }

    @Test func aFileThePersonPutInTheCategoryIsOneWhateverItsLength() {
        #expect(FieldRecording.isFieldRecording(duration: 2, manualCategory: "Field recording"))
        #expect(!FieldRecording.isFieldRecording(duration: 2, manualCategory: "Kick"))
        #expect(!FieldRecording.isFieldRecording(duration: 2, manualCategory: nil))
        #expect(FieldRecording.isFieldRecording(duration: 90, manualCategory: "Kick"), "length still counts")
    }

    @Test func aShortFileSetToFieldRecordingIsSegmentedAndBackAgain() async throws {
        let dir = TestSupport.tempDir()
        var rng = SplitMix64(seed: 3)
        try writeTestWav(dir.appendingPathComponent("birdy.wav"), seconds: 8) { t in
            (t > 1 && t < 3) || (t > 5 && t < 7) ? (rng.nextFloat() * 2 - 1) * 0.3 : 0
        }
        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        let pipeline = IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1)
        _ = await pipeline.run(onProgress: { _ in })
        let id = try #require(store.loadSamples().first).id
        #expect(store.segmentCount(sampleID: id) == 0 && store.sample(id: id)?.isFieldRecording == false)
        #expect(try store.markFieldRecordingsStale() == 0)

        // The person says it is a field recording: it counts as one at once and is queued to be read in segments.
        try store.setManualCategory(sampleID: id, "Field recording")
        #expect(store.sample(id: id)?.isFieldRecording == true)
        #expect(store.descriptorBacklog() == 0, "its descriptors come from the segments")
        #expect(try store.markFieldRecordingsStale() == 1)
        #expect(store.pendingJobs(limit: 5).first?.isFieldRecording == true)
        _ = await pipeline.run(onProgress: { _ in })
        #expect(store.segmentCount(sampleID: id) == 2)
        #expect(try store.markFieldRecordingsStale() == 0, "done, not queued again")
        #expect(store.sample(id: id)?.categoryManual == "Field recording", "their choice is kept")

        // Taking the category away makes it an ordinary sound again.
        try store.setManualCategory(sampleID: id, nil)
        #expect(store.sample(id: id)?.isFieldRecording == false)
        #expect(try store.markFieldRecordingsStale() == 1)
        _ = await pipeline.run(onProgress: { _ in })
        #expect(store.segmentCount(sampleID: id) == 0)
        #expect(try store.markFieldRecordingsStale() == 0)
    }

    @Test func compositeIsALengthWeightedUnitVector() {
        let a = SegmentEmbedding(start: 0, end: 3, embedding: [1, 0])
        let b = SegmentEmbedding(start: 5, end: 6, embedding: [0, 1])
        let c = FieldRecording.composite([a, b])
        #expect(abs(c[0] * c[0] + c[1] * c[1] - 1) < 1e-5)
        #expect(c[0] > c[1])                                   // the 3 s segment weighs three times the 1 s one
        #expect(abs(c[0] / c[1] - 3) < 1e-4)
        #expect(FieldRecording.composite([]).isEmpty)
    }

    @Test func aggregateKeepsLoudestPeakAndPowerAveragedLoudness() {
        let quiet = SoundDescriptors(loudnessDB: -40, peakDB: -30, crestDB: 10, centroidHz: 500, isLoop: true, bpm: 120)
        let loud = SoundDescriptors(loudnessDB: -10, peakDB: -3, crestDB: 7, centroidHz: 4000, isLoop: false)
        let d = FieldRecording.aggregate([(quiet, 5), (loud, 5)])
        #expect(d.peakDB == -3)
        #expect(d.loudnessDB > -14 && d.loudnessDB < -12)       // dominated by the loud half
        #expect(d.centroidHz > 3500)
        #expect(!d.isLoop && d.bpm == nil && d.keyName == nil && d.pitchHz == nil)
        #expect(abs(d.crestDB - (d.peakDB - d.loudnessDB)) < 1e-9)
    }

    @Test func segmentsRoundTripAndAreReplaced() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "field.wav", size: 1, mtime: 1)]) { _ in nil }
        let id = store.pendingJobs(limit: 1)[0].id
        func save(_ segments: [SegmentEmbedding]) throws {
            try store.save(results: [.success(id: id, duration: 120, sampleRate: 48000, channels: 2, embedding: [1, 0],
                                              fingerprint: nil, modelVersion: "m1", segments: segments)])
        }
        try save([SegmentEmbedding(start: 1, end: 4, embedding: [1, 0]), SegmentEmbedding(start: 9, end: 12, embedding: [0, 1])])
        let loaded = store.segments(sampleID: id)
        #expect(loaded.count == 2 && loaded[1].start == 9 && loaded[1].embedding == [0, 1])
        #expect(store.sample(id: id)?.isFieldRecording == true)
        try save([SegmentEmbedding(start: 2, end: 3, embedding: [1, 0])])
        #expect(store.segmentCount(sampleID: id) == 1)

        var seen: [(Int64, TimeSpan)] = []
        try store.forEachSegmentChunk(modelVersion: "m1", chunkSize: 1) { ids, spans, flat in
            #expect(flat.count == ids.count * 2)
            seen += zip(ids, spans).map { ($0, $1) }
        }
        #expect(seen.count == 1 && seen[0].1 == TimeSpan(start: 2, end: 3))
    }

    @Test func removingARootRemovesItsSegments() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "field.wav", size: 1, mtime: 1)]) { _ in nil }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: 60, sampleRate: 48000, channels: 1, embedding: [1],
                                          fingerprint: nil, modelVersion: "m1",
                                          segments: [SegmentEmbedding(start: 0, end: 1, embedding: [1])])])
        try store.removeRoot(id: root.id)
        #expect(store.segmentCount(sampleID: id) == 0)
    }

    @Test func longFilesWithoutSegmentsAreRequeuedOnce() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "long.wav", size: 1, mtime: 1),
                                                  ScannedFile(relPath: "short.wav", size: 1, mtime: 1)]) { _ in nil }
        let jobs = store.pendingJobs(limit: 10)
        let results: [IndexResult] = jobs.map {
            .success(id: $0.id, duration: $0.url.lastPathComponent == "long.wav" ? 90 : 1, sampleRate: 44100, channels: 1,
                     embedding: [1], fingerprint: nil, modelVersion: "m1")
        }
        try store.save(results: results)
        #expect(store.pendingCount() == 0)
        #expect(try store.markFieldRecordingsStale() == 1)
        #expect(store.pendingCount() == 1)
        let long = store.pendingJobs(limit: 1)[0]
        try store.save(results: [.success(id: long.id, duration: 90, sampleRate: 44100, channels: 1, embedding: [1],
                                          fingerprint: nil, modelVersion: "m1",
                                          segments: [SegmentEmbedding(start: 0, end: 1, embedding: [1])])])
        #expect(try store.markFieldRecordingsStale() == 0)
    }

    @Test func indexesALongRecordingInSegments() async throws {
        let dir = TestSupport.tempDir()
        // Tone, noise and a higher tone separated by silence, 40 s in total.
        var rng = SplitMix64(seed: 7)
        try writeTestWav(dir.appendingPathComponent("field.wav"), seconds: 40) { t in
            switch t {
            case 2..<4: return Float(sin(2 * .pi * 220 * t)) * 0.5
            case 12..<14.5: return (rng.nextFloat() * 2 - 1) * 0.3
            case 25..<27: return Float(sin(2 * .pi * 1760 * t)) * 0.4
            default: return 0
            }
        }
        try writeTestWav(dir.appendingPathComponent("short.wav"), seconds: 0.5) { Float(sin(2 * .pi * 440 * $0)) * 0.5 }

        let store = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }
        let done = await IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 1).run(onProgress: { _ in })
        #expect(done == 2)

        let field = try #require(store.loadSamples().first { $0.name == "field" })
        #expect(field.isFieldRecording && abs(field.duration - 40) < 0.1)
        let segments = store.segments(sampleID: field.id)
        #expect(segments.count == 3)
        #expect(abs(segments[1].start - 11.9) < 0.1 && abs(segments[1].end - 14.6) < 0.1)
        #expect(field.isLoop == false && field.bpm == nil)

        let short = try #require(store.loadSamples().first { $0.name == "short" })
        #expect(store.segmentCount(sampleID: short.id) == 0)
        #expect(store.pendingCount() == 0)
        #expect(try store.markFieldRecordingsStale() == 0)

        let composite = try store.embeddings(ids: [field.id])
        let norm = composite.flat.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1) < 1e-2)
    }
}
