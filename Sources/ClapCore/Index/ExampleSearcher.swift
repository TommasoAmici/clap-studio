import Foundation

public enum ExampleSearchError: Error, CustomStringConvertible {
    case notAudio(String)
    case modelMismatch
    case emptyLibrary

    public var description: String {
        switch self {
        case .notAudio(let name): return "\(name) is not an audio file Clap Studio can read."
        case .modelMismatch: return "The library was embedded with a model that is not available now, so a new file cannot be compared."
        case .emptyLibrary: return "Nothing to compare with yet. Index a folder first."
        }
    }
}

/// "Find sounds like this file": embeds any audio file (inside the library or not) and ranks the library by cosine.
public final class ExampleSearcher: @unchecked Sendable {
    private let store: LibraryStore
    private let lock = NSLock()
    private var embedder: EmbeddingProvider?
    private var index: VectorIndex?
    private let segmentCache: SegmentIndexCache

    public init(store: LibraryStore, segments: SegmentIndexCache = SegmentIndexCache()) {
        self.store = store
        self.segmentCache = segments
    }

    public func invalidate() { lock.lock(); index = nil; lock.unlock(); segmentCache.invalidate() }

    public func similar(to url: URL, limit: Int = 100) throws -> [TextHit] {
        let query = try embedding(of: url)
        let (_, vectors) = try prepare()
        let hits = vectors.topK(query: query, limit: limit).map { TextHit(sampleID: vectors.ids[$0.row], score: $0.score) }
        let segments = try segmentCache.index(store: store, modelVersion: try modelVersion()).bestMatches(query: query)
        return SegmentMerge.merge(hits, segments: segments, limit: limit)
    }

    /// What a search with this file starts from: its embedding, made the same way as the library's.
    public func embedding(of url: URL) throws -> [Float] {
        guard FolderScanner.isSupported(url) else { throw ExampleSearchError.notAudio(url.lastPathComponent) }
        let (embedder, vectors) = try prepare()
        guard vectors.count > 0 else { throw ExampleSearchError.emptyLibrary }
        let fe = embedder.frontEnd
        // Same input path as indexing, so a dropped file embeds exactly like its library copy.
        let input = try EmbeddingInput.load(url: url, frontEnd: fe, analyzer: DescriptorAnalyzer())
        return try embedder.embed(LogMelExtractor(config: fe).extract(signal: input.signal))
    }

    /// The stored embedding of a library sample, or nil when it has none.
    public func embedding(ofSample id: Int64) throws -> [Float]? {
        let found = try store.embeddings(ids: [id])
        return found.ids.isEmpty ? nil : Array(found.flat.prefix(found.dim))
    }

    /// Similarity of `query` to every sample, and where in each field recording it matches best. A field recording
    /// scores as high as its best segment.
    public func results(forQuery query: [Float]) throws -> TextSearchResult {
        let (_, vectors) = try prepare()
        guard vectors.count > 0 else { throw ExampleSearchError.emptyLibrary }
        var scores = Dictionary(uniqueKeysWithValues: vectors.topK(query: query, limit: vectors.count).map { (vectors.ids[$0.row], $0.score) })
        let segments = try segmentCache.index(store: store, modelVersion: try modelVersion()).bestMatches(query: query)
        for (id, match) in segments { scores[id] = max(scores[id] ?? -.infinity, match.score) }
        return TextSearchResult(scores: scores, segments: segments)
    }

    private func modelVersion() throws -> String {
        guard let version = store.meta("model_version") else { throw ExampleSearchError.emptyLibrary }
        return version
    }

    private func prepare() throws -> (EmbeddingProvider, VectorIndex) {
        lock.lock(); defer { lock.unlock() }
        guard let version = store.meta("model_version") else { throw ExampleSearchError.emptyLibrary }
        if embedder == nil || embedder?.version != version {
            let choice = EmbedderFactory.make()
            guard choice.provider.version == version else { throw ExampleSearchError.modelMismatch }
            embedder = choice.provider
            index = nil
        }
        if index == nil {
            var ids: [Int64] = [], flat: [Float] = []
            try store.forEachEmbeddingChunk(modelVersion: version) { chunkIDs, chunk, _ in ids += chunkIDs; flat += chunk }
            index = VectorIndex(ids: ids, vectors: flat, dim: embedder!.dimension)
        }
        return (embedder!, index!)
    }
}
