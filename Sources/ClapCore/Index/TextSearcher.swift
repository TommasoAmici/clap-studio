import Foundation

public struct TextHit: Sendable {
    public let sampleID: Int64
    public let score: Float
    /// For a field recording: the part that matched best.
    public let segment: SegmentMatch?

    public init(sampleID: Int64, score: Float, segment: SegmentMatch? = nil) {
        self.sampleID = sampleID; self.score = score; self.segment = segment
    }
}

/// Similarity of a description to every sample, and where in each field recording it matches.
public struct TextSearchResult: Sendable {
    public var scores: [Int64: Float]
    public var segments: [Int64: SegmentMatch]

    public init(scores: [Int64: Float] = [:], segments: [Int64: SegmentMatch] = [:]) {
        self.scores = scores; self.segments = segments
    }
}

/// "Describe a sound" search: embeds the text with CLAP and ranks every sample's audio embedding.
///
/// Uses the raw 512-d embeddings, not the PCA-reduced ones: text and audio sit in different regions
/// of the shared space, so the audio-centred PCA would distort text queries.
public final class TextSearcher: @unchecked Sendable {
    private let encoder: ClapTextEncoder
    private let lock = NSLock()
    private var index: VectorIndex?
    private let segmentCache: SegmentIndexCache

    public init(encoder: ClapTextEncoder, segments: SegmentIndexCache = SegmentIndexCache()) {
        self.encoder = encoder
        self.segmentCache = segments
    }

    /// Drops the cached audio vectors; they are reloaded on the next search.
    public func invalidate() {
        lock.lock(); index = nil; lock.unlock()
        segmentCache.invalidate()
    }

    public func search(_ text: String, store: LibraryStore, limit: Int = 300) throws -> [TextHit] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let vectors = try loadIndex(store: store)
        let embedded = try encoder.embed(query)
        let hits = vectors.topK(query: embedded, limit: limit).map { TextHit(sampleID: vectors.ids[$0.row], score: $0.score) }
        let segments = try segmentCache.index(store: store, modelVersion: ClapEmbedder.versionTag).bestMatches(query: embedded)
        return SegmentMerge.merge(hits, segments: segments, limit: limit)
    }

    /// Similarity of the description to every embedded sample, so the UI can combine it with other
    /// filters and re-rank without searching again.
    public func scores(for text: String, store: LibraryStore) throws -> [Int64: Float] {
        try results(for: text, store: store).scores
    }

    /// Like `scores`, with the best-matching segment of each field recording. A field recording scores as high
    /// as its best segment.
    public func results(for text: String, store: LibraryStore) throws -> TextSearchResult {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return TextSearchResult(scores: [:], segments: [:]) }
        let vectors = try loadIndex(store: store)
        let embedded = try encoder.embed(query)
        let all = vectors.topK(query: embedded, limit: vectors.count)
        var scores = Dictionary(uniqueKeysWithValues: all.map { (vectors.ids[$0.row], $0.score) })
        let segments = try segmentCache.index(store: store, modelVersion: ClapEmbedder.versionTag).bestMatches(query: embedded)
        for (id, match) in segments { scores[id] = max(scores[id] ?? -.infinity, match.score) }
        return TextSearchResult(scores: scores, segments: segments)
    }

    private func loadIndex(store: LibraryStore) throws -> VectorIndex {
        lock.lock(); defer { lock.unlock() }
        if let index { return index }
        var ids: [Int64] = [], flat: [Float] = []
        try store.forEachEmbeddingChunk(modelVersion: ClapEmbedder.versionTag) { chunkIDs, chunk, _ in
            ids += chunkIDs
            flat += chunk
        }
        let built = VectorIndex(ids: ids, vectors: flat, dim: 512)
        index = built
        return built
    }
}
