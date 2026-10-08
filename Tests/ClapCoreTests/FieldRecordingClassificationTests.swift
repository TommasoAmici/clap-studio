import Foundation
import Testing
@testable import ClapCore

@Suite struct FieldRecordingClassificationTests {
    private static let axes = ["dark": 0, "happy": 1, "epic": 2, "calm": 3, "kick": 0, "snare": 1]
    private static func fake(_ text: String) -> [Float] {
        var v = [Float](repeating: 0.01, count: 4)
        for (word, axis) in axes where text.contains(word) { v[axis] = 1 }
        let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
        return v.map { $0 / n }
    }

    private func unit(_ v: [Float]) -> [Float] {
        let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
        return v.map { $0 / n }
    }

    @Test func longFilesAreFieldRecordingsWhateverTheySoundLike() throws {
        #expect(SoundCategories.names.last == "Field recording")
        #expect(!SoundCategories.all.map(\.name).contains("Field recording"))
        #expect(SoundCategories.names.count < 48, "the map palette has 48 colours, one is for unknown")

        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        _ = try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "kick.wav", size: 1, mtime: 1),
                                                      ScannedFile(relPath: "long.wav", size: 1, mtime: 1)]) { $0 }
        let results: [IndexResult] = store.pendingJobs(limit: 2).map {
            .success(id: $0.id, duration: $0.url.lastPathComponent == "long.wav" ? 300 : 1, sampleRate: 44100, channels: 1,
                     embedding: Self.fake("kick"), fingerprint: nil, modelVersion: ClapEmbedder.versionTag)
        }
        try store.save(results: results)
        let categorizer = try Categorizer(embed: { Self.fake($0) }, categories: [("Kick", ["a kick"]), ("Snare", ["a snare"])])
        try store.categorize(with: categorizer)
        let byName = Dictionary(uniqueKeysWithValues: store.loadSamples().map { ($0.name, $0) })
        #expect(byName["kick"]?.effectiveCategory == "Kick")
        #expect(byName["long"]?.effectiveCategory == "Field recording")
        #expect(SoundCategories.symbol(for: "Field recording") == "leaf")
    }

    @Test func fieldRecordingMoodsAreTheUnionOfItsSegmentsAndJudgedAgainstRegularSamples() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        var files = (0..<40).map { ScannedFile(relPath: "s\($0).wav", size: 1, mtime: 1) }
        files.append(ScannedFile(relPath: "field.wav", size: 1, mtime: 1))
        _ = try store.sync(rootID: root.id, scanned: files) { $0 }

        // 40 neutral samples, each a little different; the recording has a dark, a happy and a neutral segment.
        let neutral = (0..<40).map { i -> [Float] in
            var v: [Float] = [0.5, 0.5, 0.5, 1]
            v[i % 3] += Float(i % 5) * 0.01
            return unit(v)
        }
        let segments = [
            SegmentEmbedding(start: 0, end: 5, embedding: Self.fake("dark")),
            SegmentEmbedding(start: 10, end: 15, embedding: Self.fake("happy")),
            SegmentEmbedding(start: 20, end: 25, embedding: unit([0.5, 0.5, 0.5, 1])),
        ]
        let results: [IndexResult] = store.pendingJobs(limit: 100).map { job in
            let name = job.url.lastPathComponent
            if name == "field.wav" {
                return .success(id: job.id, duration: 120, sampleRate: 48000, channels: 1,
                                embedding: FieldRecording.composite(segments), fingerprint: nil,
                                modelVersion: ClapEmbedder.versionTag, segments: segments)
            }
            let index = Int(name.dropFirst().dropLast(4))!
            return .success(id: job.id, duration: 1, sampleRate: 44100, channels: 1, embedding: neutral[index],
                            fingerprint: nil, modelVersion: ClapEmbedder.versionTag)
        }
        try store.save(results: results)

        let scorer = try MoodScorer(embed: { Self.fake($0) }, moods: [
            ("Dark", ["a dark sound"]), ("Happy", ["a happy sound"]), ("Epic", ["an epic sound"]),
        ])
        try store.assignMoods(with: scorer)
        let samples = store.loadSamples()
        #expect(samples.first { $0.name == "field" }?.moods == ["Dark", "Happy"])
        // The recording's segments do not shift the standard they are judged by: s0 stays unremarkable.
        #expect(samples.first { $0.name == "s0" }?.moods == [])
    }
}

@Suite struct FieldRecordingFilterTests {
    private func sample(duration: Double, loop: Bool = false) -> SampleRecord {
        var s = SampleRecord(id: 1, rootID: 1, rootPath: "/", relPath: "a.wav", name: "a", ext: "wav", duration: duration,
                             sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok, useCount: 0,
                             lastUsed: nil, cueCount: 0)
        s.isLoop = loop
        return s
    }

    @Test func kindFilterSeparatesFieldRecordingsFromHitsAndLoops() {
        let hit = sample(duration: 1), loop = sample(duration: 8, loop: true), field = sample(duration: 45)
        var filter = DescriptorFilter()
        filter.kind = .fieldRecording
        #expect(filter.isActive && filter.matches(field) && !filter.matches(hit) && !filter.matches(loop))
        filter.kind = .oneShot
        #expect(filter.matches(hit) && !filter.matches(field))
        filter.kind = .loop
        #expect(filter.matches(loop) && !filter.matches(field))
        #expect(sample(duration: 29.99).isFieldRecording == false && sample(duration: 30).isFieldRecording)
    }
}
