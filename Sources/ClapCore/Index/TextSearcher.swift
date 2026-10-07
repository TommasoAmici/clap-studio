import Foundation

public struct TextHit: Sendable {
    public let sampleID: Int64
    public let score: Float
}

/// "Describe a sound" search: embeds the text with CLAP and ranks every sample's audio embedding.
///
/// Uses the raw 512-d embeddings, not the PCA-reduced ones: text and audio sit in different regions
/// of the shared space, so the audio-centred PCA would distort text queries.
public final class TextSearcher: @unchecked Sendable {
    private let encoder: ClapTextEncoder
    private let lock = NSLock()
    private var index: VectorIndex?

    public init(encoder: ClapTextEncoder) { self.encoder = encoder }

    /// Drops the cached audio vectors; they are reloaded on the next search.
    public func invalidate() {
        lock.lock(); index = nil; lock.unlock()
    }

    public func search(_ text: String, store: LibraryStore, limit: Int = 300) throws -> [TextHit] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let vectors = try loadIndex(store: store)
        let embedded = try encoder.embed(query)
        return vectors.topK(query: embedded, limit: limit).map { TextHit(sampleID: vectors.ids[$0.row], score: $0.score) }
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
