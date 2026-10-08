import Foundation
import Testing
@testable import ClapCore

@Suite struct FieldSoundsTests {
    private static let axes = ["bird": 0, "water": 1, "speech": 2]
    private static func fake(_ text: String) -> [Float] {
        var v = [Float](repeating: 0.01, count: 4)
        for (word, axis) in axes where text.contains(word) { v[axis] = 1 }
        let n = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
        return v.map { $0 / n }
    }

    private func categorizer() throws -> Categorizer {
        try Categorizer(embed: { Self.fake($0) }, categories: [("Birds", ["a bird"]), ("Water", ["water"]), ("Speech", ["speech"])])
    }

    @Test func vocabularyHasEnvironmentalCategoriesForEverySample() {
        let all = SoundCategories.all.map(\.name)
        #expect(all.contains("Birds") && all.contains("Water") && all.contains("Speech"))
        #expect(SoundCategories.names.last == "Field recording", "field recording stays last and is not phrase-based")
        let vocabulary = SoundCategories.segmentVocabulary.map(\.name)
        #expect(vocabulary.contains("Birds") && !vocabulary.contains("Ambience") && !vocabulary.contains("FX"))
        #expect(SoundCategories.sortedSounds(["Water", "Kick", "Birds"]) == ["Kick", "Birds", "Water"])
        #expect(SoundCategories.symbol(for: "Birds") != "tag")
    }

    @Test func classifyTopKeepsSeveralLabelsAboveTheCutOff() throws {
        let c = try categorizer()
        let mix = zip(Self.fake("bird"), Self.fake("water")).map { $0 + $1 }
        let flat = Self.fake("bird") + mix + [0.5, 0.5, 0.5, 0.5]
        let result = c.classifyTop(flat: flat, count: 3, limit: 2, minimum: 0.2)
        #expect(result[0].map(\.name) == ["Birds"])
        #expect(Set(result[1].map(\.name)) == ["Birds", "Water"])
        #expect(result[1].count == 2 && result[1][0].confidence >= result[1][1].confidence)
        #expect(c.classifyTop(flat: mix, count: 1, limit: 1, minimum: 0.2)[0].count == 1)
    }

    private func recording() throws -> (LibraryStore, Int64) {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "field.wav", size: 1, mtime: 1)]) { $0 }
        let id = store.pendingJobs(limit: 1)[0].id
        try save(store, id, segments: [
            SegmentEmbedding(start: 0, end: 10, embedding: Self.fake("bird")),
            SegmentEmbedding(start: 10, end: 20, embedding: Self.fake("bird")),          // continues the birds: merged
            SegmentEmbedding(start: 30, end: 40, embedding: Self.fake("water")),
            SegmentEmbedding(start: 50, end: 50.5, embedding: Self.fake("speech")),      // too short to name
            SegmentEmbedding(start: 60, end: 65, embedding: Self.fake("bird")),
        ])
        return (store, id)
    }

    private func save(_ store: LibraryStore, _ id: Int64, segments: [SegmentEmbedding]) throws {
        try store.save(results: [.success(id: id, duration: 120, sampleRate: 48000, channels: 1,
                                          embedding: FieldRecording.composite(segments), fingerprint: nil,
                                          modelVersion: ClapEmbedder.versionTag, segments: segments)])
    }

    @Test func segmentsAreNamedAndMergedPerSound() throws {
        let (store, id) = try recording()
        #expect(store.soundsAreStale())
        try store.labelSegments(with: categorizer())
        #expect(!store.soundsAreStale())

        let found = store.soundOccurrences(sampleID: id)
        #expect(found.map(\.name) == ["Birds", "Water"], "longest first; the 0.5 s speech is skipped")
        #expect(found[0].spans == [TimeSpan(start: 0, end: 20), TimeSpan(start: 60, end: 65)])
        #expect(found[0].total == 25 && found[1].total == 10)
        #expect(store.sample(id: id)?.sounds == ["Birds", "Water"])
    }

    @Test func relabellingReplacesAndNewSegmentsMakeLabelsStale() throws {
        let (store, id) = try recording()
        let c = try categorizer()
        try store.labelSegments(with: c)
        try store.labelSegments(with: c)
        #expect(store.soundOccurrences(sampleID: id).count == 2, "recomputing never duplicates")

        try save(store, id, segments: [SegmentEmbedding(start: 0, end: 8, embedding: Self.fake("speech"))])
        #expect(store.soundOccurrences(sampleID: id).isEmpty, "re-indexing drops the old labels")
        #expect(store.soundsAreStale())
        try store.labelSegments(with: c)
        #expect(store.sample(id: id)?.sounds == ["Speech"])
    }

    @Test func categoryFilterAlsoMatchesSoundsHeardInARecording() throws {
        let (store, id) = try recording()
        try store.labelSegments(with: categorizer())
        let field = try #require(store.sample(id: id))
        var filter = DescriptorFilter()
        filter.category = "Birds"
        #expect(filter.matches(field), "a recording with birds matches the Birds category")
        filter.category = "Speech"
        #expect(!filter.matches(field))
        var bird = field
        bird.sounds = []
        bird.category = "Birds"
        filter.category = "Birds"
        #expect(filter.matches(bird), "an ordinary bird sample still matches by its own category")
    }
}
