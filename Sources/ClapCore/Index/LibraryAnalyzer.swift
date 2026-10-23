import Foundation

/// Everything the UI needs for similarity search and the map, loaded from disk.
public struct AnalysisSnapshot: Sendable {
    public let index: VectorIndex
    /// Cluster id per index row.
    public var clusters: [Int32]
    /// Interleaved map coordinates per index row.
    public var xy: [Float]
    public var clusterCount: Int { Int((clusters.max() ?? -1) + 1) }
}

/// Computes and caches derived data. Warm start only reads the DB; heavy work
/// (PCA, clustering, layout) runs only when the library changed meaningfully.
public final class LibraryAnalyzer: @unchecked Sendable {
    public static let fullRefreshFraction = 0.05
    private let store: LibraryStore
    private let seed: UInt64

    public init(store: LibraryStore, seed: UInt64 = 42) {
        self.store = store
        self.seed = seed
    }

    public static func defaultClusterCount(for n: Int) -> Int {
        max(4, min(20, Int((Double(n).squareRoot() / 12).rounded())))
    }

    /// Loads cached analysis without any computation (nil when nothing is cached).
    public func loadSnapshot(modelVersion: String) -> AnalysisSnapshot? {
        let c = store.loadCoords(modelVersion: modelVersion)
        guard !c.ids.isEmpty, c.dim > 0 else { return nil }
        return AnalysisSnapshot(index: VectorIndex(ids: c.ids, vectors: c.pca, dim: c.dim),
                                clusters: c.clusters, xy: c.xy)
    }

    /// Brings derived data up to date and returns a snapshot.
    public func refresh(modelVersion: String, force: Bool = false, clusterCount: Int? = nil,
                        status: @escaping @Sendable (String) -> Void = { _ in }) throws -> AnalysisSnapshot? {
        let embedded = store.embeddedCount(modelVersion: modelVersion)
        guard embedded >= 2 else { return nil }
        let missing = store.sampleIDsMissingCoords(modelVersion: modelVersion)
        let projection = store.loadProjection()
        let cached = embedded - missing.count

        let needFull = force || projection == nil || projection?.modelVersion != modelVersion
            || cached < 50 || Double(missing.count) > Self.fullRefreshFraction * Double(embedded)
        if needFull {
            try computeAll(modelVersion: modelVersion, embedded: embedded,
                           clusterCount: clusterCount ?? Self.defaultClusterCount(for: embedded), status: status)
        } else if !missing.isEmpty, let projection {
            status("Adding \(missing.count) new samples to the map")
            try placeNew(ids: missing, projection: projection.model, modelVersion: modelVersion)
        }
        return loadSnapshot(modelVersion: modelVersion)
    }

    /// Re-runs only k-means (cheap) when the user changes the number of clusters.
    public func recluster(modelVersion: String, k: Int) throws -> AnalysisSnapshot? {
        guard var snapshot = loadSnapshot(modelVersion: modelVersion) else { return nil }
        let result = KMeans.run(vectors: snapshot.index.vectors, count: snapshot.index.count,
                                dim: snapshot.index.dim, k: k, seed: seed)
        try store.saveCentroids(result.centroids, k: result.k, dim: result.dim)
        try store.updateClusters(zip(snapshot.index.ids, result.assignments).map { ($0, Int($1)) })
        snapshot.clusters = result.assignments
        return snapshot
    }

    // MARK: full computation

    private func computeAll(modelVersion: String, embedded: Int, clusterCount: Int,
                            status: @escaping @Sendable (String) -> Void) throws {
        status("Fitting projection")
        guard let dim = store.embeddedDimension(modelVersion: modelVersion) else {
            throw DBError.sql("No stored embeddings were found for analysis")
        }
        let pca = try PCAModel.fit(dim: dim, maxComponents: 128) { body in
            try store.forEachEmbeddingChunk(modelVersion: modelVersion) { _, flat, rows in body(flat, rows) }
        }

        var ids: [Int64] = [], projected: [Float] = []
        try store.forEachEmbeddingChunk(modelVersion: modelVersion) { chunkIDs, flat, rows in
            ids += chunkIDs
            projected += pca.project(flat, count: rows)
        }
        let n = ids.count

        status("Clustering \(n) samples")
        let km = KMeans.run(vectors: projected, count: n, dim: pca.k, k: clusterCount, seed: seed)

        status("Laying out the map")
        let xy = MapLayout.layout(vectors: projected, count: n, dim: pca.k, seed: seed)

        status("Saving")
        try store.clearCoords()
        let rows = (0..<n).map { i in
            CoordRow(sampleID: ids[i], pca: Array(projected[(i * pca.k)..<((i + 1) * pca.k)]),
                     cluster: Int(km.assignments[i]), x: xy[i * 2], y: xy[i * 2 + 1])
        }
        for chunk in stride(from: 0, to: rows.count, by: 2000) {
            try store.saveCoords(Array(rows[chunk..<min(chunk + 2000, rows.count)]))
        }
        try store.saveCentroids(km.centroids, k: km.k, dim: pca.k)
        try store.saveProjection(pca, modelVersion: modelVersion, sampleCount: n)
    }

    // MARK: incremental

    private func placeNew(ids: [Int64], projection: PCAModel, modelVersion: String) throws {
        guard let existing = loadSnapshot(modelVersion: modelVersion) else { return }
        let fetched = try store.embeddings(ids: ids)
        let n = fetched.ids.count
        guard n > 0, fetched.dim == projection.dim else { return }

        let projected = projection.project(fetched.flat, count: n)
        let xy = MapLayout.place(vectors: projected, count: n, dim: projection.k, among: existing.index,
                                 coords: existing.xy, seed: seed &+ UInt64(existing.index.count))
        var clusters = [Int32](repeating: 0, count: n)
        if let centroids = store.loadCentroids() {
            clusters = KMeans.assign(vectors: projected, count: n, dim: projection.k,
                                     centroids: centroids.flat, k: centroids.k)
        }
        let rows = (0..<n).map { i in
            CoordRow(sampleID: fetched.ids[i], pca: Array(projected[(i * projection.k)..<((i + 1) * projection.k)]),
                     cluster: Int(clusters[i]), x: xy[i * 2], y: xy[i * 2 + 1])
        }
        try store.saveCoords(rows)
    }
}
