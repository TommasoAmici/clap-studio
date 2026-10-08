import Foundation
import Testing
@testable import ClapCore

@Suite struct SegmentIndexTests {
    /// Two recordings: #10 has a kick-like segment at 4 s and an ambience-like one at 30 s; #11 only ambience.
    private func index() -> SegmentIndex {
        SegmentIndex(sampleIDs: [10, 10, 11],
                     spans: [TimeSpan(start: 4, end: 6), TimeSpan(start: 30, end: 40), TimeSpan(start: 1, end: 9)],
                     vectors: [1, 0, 0,   0, 1, 0,   0, 0.6, 0.8], dim: 3)
    }

    @Test func reportsTheBestSegmentOfEachRecording() {
        let kick = index().bestMatches(query: [1, 0, 0])
        #expect(kick[10]?.start == 4 && kick[10]?.end == 6 && kick[10]!.score > 0.99)
        #expect(kick[11]!.score < 0.01)
        let ambience = index().bestMatches(query: [0, 1, 0])
        #expect(ambience[10]?.start == 30)
        #expect(ambience[11]?.start == 1 && abs(ambience[11]!.score - 0.6) < 1e-5)
    }

    @Test func excludesTheReferencesOwnSegments() {
        let matches = index().bestMatches(query: [1, 0, 0], excluding: 10)
        #expect(matches[10] == nil && matches[11] != nil)
        #expect(index().bestMatches(query: [1, 0]).isEmpty, "a query of the wrong size matches nothing")
        #expect(SegmentIndex.empty.bestMatches(query: [1, 0, 0]).isEmpty)
    }

    @Test func aRecordingScoresAsWellAsItsBestSegmentAndKeepsItsPlace() {
        let hits = [TextHit(sampleID: 1, score: 0.5), TextHit(sampleID: 10, score: 0.1), TextHit(sampleID: 2, score: 0.05)]
        let segments: [Int64: SegmentMatch] = [10: SegmentMatch(start: 4, end: 6, score: 0.9), 11: SegmentMatch(start: 1, end: 9, score: 0.3)]
        let merged = SegmentMerge.merge(hits, segments: segments, limit: 3)
        #expect(merged.map(\.sampleID) == [10, 1, 11], "10 jumps to the top, 11 beats the weakest hit and joins")
        #expect(merged[0].score == 0.9 && merged[0].segment?.start == 4)
        #expect(merged[1].segment == nil)
        // Under the limit nothing is cut, so every recording joins however weak.
        #expect(SegmentMerge.merge(hits, segments: segments, limit: 10).count == 4)
        #expect(SegmentMerge.merge(hits, segments: [:], limit: 3).map(\.sampleID) == [1, 10, 2])
    }

    @Test func loadsFromTheStoreAndIsCached() throws {
        let (store, _) = try TestSupport.makeStore()
        let root = try store.addRoot(path: "/tmp/x")
        try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "f.wav", size: 1, mtime: 1)]) { $0 }
        let id = store.pendingJobs(limit: 1)[0].id
        try store.save(results: [.success(id: id, duration: 90, sampleRate: 48000, channels: 1, embedding: [1, 0],
                                          fingerprint: nil, modelVersion: "m",
                                          segments: [SegmentEmbedding(start: 3, end: 8, embedding: [0, 1]),
                                                     SegmentEmbedding(start: 20, end: 25, embedding: [1, 0])])])
        let cache = SegmentIndexCache()
        let loaded = try cache.index(store: store, modelVersion: "m")
        #expect(loaded.count == 2 && loaded.dim == 2)
        #expect(loaded.bestMatches(query: [0, 1])[id]?.start == 3)
        #expect(try cache.index(store: store, modelVersion: "m") === loaded)
        cache.invalidate()
        #expect(try cache.index(store: store, modelVersion: "m") !== loaded)
        #expect(try cache.index(store: store, modelVersion: "other").count == 0)
    }
}
