import Foundation

public struct CoordRow: Sendable {
    public let sampleID: Int64
    public let pca: [Float]
    public let cluster: Int
    public let x: Float
    public let y: Float
    public init(sampleID: Int64, pca: [Float], cluster: Int, x: Float, y: Float) {
        self.sampleID = sampleID; self.pca = pca; self.cluster = cluster; self.x = x; self.y = y
    }
}

public struct StoredProjection: Sendable {
    public let model: PCAModel
    public let modelVersion: String
    public let sampleCount: Int
}

/// Persistence of derived data (PCA, centroids, cluster ids, map coordinates).
extension LibraryStore {
    /// Samples that take part in the similarity map. Temporary roots (a USB stick) are left out.
    static let embeddedFilter = "status = 'ok' AND model_version = ? AND embedding IS NOT NULL AND root_id IN (SELECT id FROM roots WHERE transient = 0)"

    public func embeddedCount(modelVersion: String) -> Int {
        Int((try? db.scalarInt("SELECT COUNT(*) FROM samples WHERE \(Self.embeddedFilter)",
                               [.text(modelVersion)])) ?? 0)
    }

    /// Streams embeddings (id order) in chunks of rows x dim floats.
    public func forEachEmbeddingChunk(modelVersion: String, chunkSize: Int = 4096,
                                      _ body: ([Int64], [Float], Int) -> Void) throws {
        var lastID: Int64 = 0
        while true {
            let rows = try db.query("""
                SELECT id, embedding FROM samples
                WHERE \(Self.embeddedFilter) AND id > ? ORDER BY id LIMIT ?
                """, [.text(modelVersion), .int(lastID), .int(Int64(chunkSize))]) { ($0.int(0), $0.blob(1)) }
            if rows.isEmpty { return }
            var flat: [Float] = []
            for (_, blob) in rows { flat += VectorCodec.decodeFloat16(blob) }
            body(rows.map(\.0), flat, rows.count)
            lastID = rows.last!.0
        }
    }

    public func embeddings(ids: [Int64]) throws -> (ids: [Int64], flat: [Float], dim: Int) {
        var outIDs: [Int64] = [], flat: [Float] = [], dim = 0
        for batch in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = batch.map { _ in "?" }.joined(separator: ",")
            let rows = try db.query("SELECT id, embedding FROM samples WHERE id IN (\(marks)) ORDER BY id",
                                    batch.map { .int($0) }) { ($0.int(0), $0.blob(1)) }
            for (id, blob) in rows {
                let v = VectorCodec.decodeFloat16(blob)
                dim = v.count; flat += v; outIDs.append(id)
            }
        }
        return (outIDs, flat, dim)
    }

    // MARK: projection and centroids

    public func saveProjection(_ model: PCAModel, modelVersion: String, sampleCount: Int) throws {
        try db.run("""
            INSERT OR REPLACE INTO projection(id, model_version, dim, k, mean, components, sample_count)
            VALUES(1, ?, ?, ?, ?, ?, ?)
            """, [.text(modelVersion), .int(Int64(model.dim)), .int(Int64(model.k)),
                  .blob(VectorCodec.encodeFloat32(model.mean)),
                  .blob(VectorCodec.encodeFloat32(model.components)), .int(Int64(sampleCount))])
    }

    public func loadProjection() -> StoredProjection? {
        (try? db.query("SELECT model_version, dim, k, mean, components, sample_count FROM projection WHERE id = 1") {
            StoredProjection(
                model: PCAModel(dim: Int($0.int(1)), k: Int($0.int(2)),
                                mean: VectorCodec.decodeFloat32($0.blob(3)),
                                components: VectorCodec.decodeFloat32($0.blob(4))),
                modelVersion: $0.text(0), sampleCount: Int($0.int(5)))
        })?.first
    }

    public func saveCentroids(_ centroids: [Float], k: Int, dim: Int) throws {
        try db.transaction {
            try db.run("DELETE FROM centroids")
            for c in 0..<k {
                try db.run("INSERT INTO centroids(cluster, vec) VALUES(?, ?)",
                           [.int(Int64(c)), .blob(VectorCodec.encodeFloat32(Array(centroids[(c * dim)..<((c + 1) * dim)])))])
            }
        }
    }

    public func loadCentroids() -> (flat: [Float], k: Int)? {
        let rows = (try? db.query("SELECT vec FROM centroids ORDER BY cluster") { VectorCodec.decodeFloat32($0.blob(0)) }) ?? []
        return rows.isEmpty ? nil : (rows.flatMap { $0 }, rows.count)
    }

    // MARK: coordinates

    public func saveCoords(_ rows: [CoordRow]) throws {
        try db.transaction {
            for r in rows {
                try db.run("INSERT OR REPLACE INTO sample_coords(sample_id, pca, cluster, x, y) VALUES(?, ?, ?, ?, ?)",
                           [.int(r.sampleID), .blob(VectorCodec.encodeFloat32(r.pca)), .int(Int64(r.cluster)),
                            .double(Double(r.x)), .double(Double(r.y))])
            }
        }
    }

    public func clearCoords() throws { try db.run("DELETE FROM sample_coords") }

    public func updateClusters(_ assignments: [(id: Int64, cluster: Int)]) throws {
        try db.transaction {
            for a in assignments {
                try db.run("UPDATE sample_coords SET cluster = ? WHERE sample_id = ?", [.int(Int64(a.cluster)), .int(a.id)])
            }
        }
    }

    public func sampleIDsMissingCoords(modelVersion: String) -> [Int64] {
        (try? db.query("""
            SELECT s.id FROM samples s LEFT JOIN sample_coords c ON c.sample_id = s.id
            WHERE s.\(Self.embeddedFilter) AND c.sample_id IS NULL ORDER BY s.id
            """, [.text(modelVersion)]) { $0.int(0) }) ?? []
    }

    /// All coordinates for currently embedded samples (id order).
    public func loadCoords(modelVersion: String) -> (ids: [Int64], pca: [Float], dim: Int, clusters: [Int32], xy: [Float]) {
        var ids: [Int64] = [], pca: [Float] = [], clusters: [Int32] = [], xy: [Float] = []
        var dim = 0
        _ = try? db.query("""
            SELECT c.sample_id, c.pca, c.cluster, c.x, c.y FROM sample_coords c
            JOIN samples s ON s.id = c.sample_id
            WHERE s.\(Self.embeddedFilter) ORDER BY c.sample_id
            """, [.text(modelVersion)]) { row -> Int in
            let v = VectorCodec.decodeFloat32(row.blob(1))
            dim = v.count; pca += v
            ids.append(row.int(0)); clusters.append(Int32(row.int(2)))
            xy.append(Float(row.double(3))); xy.append(Float(row.double(4)))
            return 0
        }
        return (ids, pca, dim, clusters, xy)
    }
}
