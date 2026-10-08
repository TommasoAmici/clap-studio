import Accelerate
import Foundation

/// In-memory cosine index over the segments of all field recordings. Answers "where in each recording is the
/// part that best matches this query?". Brute force, like `VectorIndex`.
public final class SegmentIndex: @unchecked Sendable {
    /// Owning sample of every segment row.
    public let sampleIDs: [Int64]
    public let spans: [TimeSpan]
    public let dim: Int
    private let vectors: [Float]

    public var count: Int { sampleIDs.count }

    public init(sampleIDs: [Int64], spans: [TimeSpan], vectors: [Float], dim: Int) {
        precondition(sampleIDs.count == spans.count && vectors.count == sampleIDs.count * dim)
        self.sampleIDs = sampleIDs; self.spans = spans; self.vectors = vectors; self.dim = dim
    }

    public static let empty = SegmentIndex(sampleIDs: [], spans: [], vectors: [], dim: 0)

    public static func load(store: LibraryStore, modelVersion: String) throws -> SegmentIndex {
        var ids: [Int64] = [], spans: [TimeSpan] = [], flat: [Float] = []
        try store.forEachSegmentChunk(modelVersion: modelVersion) { chunkIDs, chunkSpans, chunk in
            ids += chunkIDs; spans += chunkSpans; flat += chunk
        }
        guard !ids.isEmpty else { return .empty }
        return SegmentIndex(sampleIDs: ids, spans: spans, vectors: flat, dim: flat.count / ids.count)
    }

    /// For each field recording, its segment closest to `query`. `excluding` leaves out one recording (the
    /// reference of a "find similar" search, whose own segments would match themselves).
    public func bestMatches(query: [Float], excluding: Int64? = nil) -> [Int64: SegmentMatch] {
        guard count > 0, query.count == dim else { return [:] }
        var scores = [Float](repeating: 0, count: count)
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(count), Int32(dim), 1, vectors, Int32(dim), query, 1, 0, &scores, 1)
        var best: [Int64: SegmentMatch] = [:]
        for row in 0..<count where sampleIDs[row] != excluding {
            let score = scores[row]
            if let current = best[sampleIDs[row]], current.score >= score { continue }
            best[sampleIDs[row]] = SegmentMatch(start: spans[row].start, end: spans[row].end, score: score)
        }
        return best
    }
}

/// Loads the segment index once and shares it between the searches; dropped when the library changes.
public final class SegmentIndexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: (version: String, index: SegmentIndex)?

    public init() {}

    public func invalidate() { lock.lock(); cached = nil; lock.unlock() }

    public func index(store: LibraryStore, modelVersion: String) throws -> SegmentIndex {
        lock.lock(); defer { lock.unlock() }
        if let cached, cached.version == modelVersion { return cached.index }
        let loaded = try SegmentIndex.load(store: store, modelVersion: modelVersion)
        cached = (modelVersion, loaded)
        return loaded
    }
}

public enum SegmentMerge {
    /// Folds segment matches into ranked hits. A field recording scores as well as its best segment (the
    /// composite averages unrelated sounds, so it alone under-rates them) and remembers where that is.
    /// Recordings whose segment beats the lowest hit join the list when it was cut at `limit`.
    public static func merge(_ hits: [TextHit], segments: [Int64: SegmentMatch], limit: Int) -> [TextHit] {
        guard !segments.isEmpty else { return hits }
        var byID: [Int64: TextHit] = [:]
        for hit in hits {
            if let m = segments[hit.sampleID] {
                byID[hit.sampleID] = TextHit(sampleID: hit.sampleID, score: max(hit.score, m.score), segment: m)
            } else {
                byID[hit.sampleID] = hit
            }
        }
        let cutoff = hits.count >= limit ? (hits.last?.score ?? -.infinity) : -.infinity
        for (id, m) in segments where byID[id] == nil && m.score > cutoff {
            byID[id] = TextHit(sampleID: id, score: m.score, segment: m)
        }
        return Array(byID.values.sorted { ($0.score, $1.sampleID) > ($1.score, $0.sampleID) }.prefix(limit))
    }
}
