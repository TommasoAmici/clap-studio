import Testing
@testable import ClapCore

@Suite struct SimilarityCancellationTests {
    private func record(_ id: Int64) -> SampleRecord {
        var sample = SampleRecord(id: id, rootID: 1, rootPath: "/", relPath: "s\(id).wav", name: "s\(id)", ext: "wav",
                                  duration: 1, sampleRate: 44_100, channels: 1, size: 1, mtime: 0,
                                  status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        sample.pitchHz = 220
        return sample
    }

    @Test func cancelledRankingDoesNotPublishPartialMatches() {
        let index = VectorIndex(ids: [1, 2, 3, 4], vectors: [1, 0, 0.9, 0.4, 0.8, 0.6, 0.7, 0.7], dim: 2)
        var lookedUp = 0
        let result = AspectSimilarity.rank(reference: record(1), index: index,
                                           weights: AspectWeights(pitch: 1), limit: 3,
                                           isCancelled: { lookedUp >= 1 }) { id in
            lookedUp += 1
            return record(id)
        }
        #expect(result.isEmpty, "A superseded ranking must not publish the matches collected so far")
        #expect(lookedUp == 1, "A superseded ranking stops scoring the remaining candidates")
    }

    @Test func cancelledDefaultRankingReturnsNoMatches() {
        let index = VectorIndex(ids: [1, 2], vectors: [1, 0, 0, 1], dim: 2)
        let result = AspectSimilarity.rank(reference: record(1), index: index, weights: AspectWeights(),
                                           limit: 1, isCancelled: { true }) { _ in nil }
        #expect(result.isEmpty, "A cancelled request should not return stale matches")
    }
}
