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
        guard FolderScanner.isSupported(url) else { throw ExampleSearchError.notAudio(url.lastPathComponent) }
        let (embedder, vectors) = try prepare()
        guard vectors.count > 0 else { throw ExampleSearchError.emptyLibrary }
        let fe = embedder.frontEnd
        // Same input path as indexing, so a dropped file embeds exactly like its library copy.
        let input = try EmbeddingInput.load(url: url, frontEnd: fe, analyzer: DescriptorAnalyzer())
        let query = try embedder.embed(LogMelExtractor(config: fe).extract(signal: input.signal))
        let hits = vectors.topK(query: query, limit: limit).map { TextHit(sampleID: vectors.ids[$0.row], score: $0.score) }
        let segments = try segmentCache.index(store: store, modelVersion: embedder.version).bestMatches(query: query)
        return SegmentMerge.merge(hits, segments: segments, limit: limit)
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
