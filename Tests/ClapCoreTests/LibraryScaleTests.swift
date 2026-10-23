import Foundation
import Testing
@testable import ClapCore

@Suite struct LibraryScaleTests {
    private let count = 100_000

    @Test func cachedLibraryKeepsEverySampleAndStreamsBoundedChunks() throws {
        let (store, directory) = try TestSupport.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try store.addRoot(path: directory.appendingPathComponent("samples").path)
        let embedding = VectorCodec.encodeFloat16([1, 0, 0, 0])
        try store.db.run("""
            WITH RECURSIVE rows(i) AS (VALUES(1) UNION ALL SELECT i + 1 FROM rows WHERE i < ?)
            INSERT INTO samples(id, root_id, rel_path, name, ext, size, mtime, status, model_version, embedding)
            SELECT i, ?, 'sample-' || i || '.wav', 'sample-' || i, 'wav', 100, 1, 'ok', 'scale', ? FROM rows
            """, [.int(Int64(count)), .int(root.id), .blob(embedding)])
        let projected = VectorCodec.encodeFloat32([1, 0])
        try store.db.run("""
            INSERT INTO sample_coords(sample_id, pca, cluster, x, y)
            SELECT id, ?, id % 16, id * 0.001, 0 FROM samples
            """, [.blob(projected)])

        #expect(store.embeddedDimension(modelVersion: "scale") == 4,
                "reading the embedding width must not walk a hundred thousand rows")
        #expect(store.embeddedDimension(modelVersion: "missing") == nil)
        #expect(store.embeddedCount(modelVersion: "scale") == count)
        var seen: [Int64] = []
        var largestChunk = 0
        try store.forEachEmbeddingChunk(modelVersion: "scale") { ids, flat, rows in
            largestChunk = max(largestChunk, rows)
            #expect(flat.count == rows * 4, "the last, partial chunk keeps its embedding width")
            seen += ids
        }
        #expect(seen == (1...count).map(Int64.init), "streaming crosses the old target and keeps ID order")
        #expect(largestChunk == 4096, "a larger library must not enlarge the streaming working set")

        let reopened = try LibraryStore(path: directory.appendingPathComponent("lib.sqlite").path)
        #expect(reopened.loadSamples().count == count, "relaunch restores every row without re-indexing")
        let snapshot = try #require(LibraryAnalyzer(store: reopened).loadSnapshot(modelVersion: "scale"))
        #expect(snapshot.index.count == count && snapshot.xy.count == count * 2)
        #expect(snapshot.index.row(forID: Int64(count)) == count - 1,
                "the last sample remains searchable after loading cached analysis")
    }

    @Test func searchFindsTheBestSoundAtTheEndOfAHundredThousandRows() {
        let dim = 128
        var vectors = [Float](repeating: 0, count: count * dim)
        for row in 0..<count { vectors[row * dim] = 1 }
        vectors[(count - 1) * dim] = 0
        vectors[(count - 1) * dim + 1] = 1
        let index = VectorIndex(ids: (1...count).map(Int64.init), vectors: vectors, dim: dim)
        var query = [Float](repeating: 0, count: dim)
        query[1] = 1
        let best = index.topK(query: query, limit: 5)
        #expect(best.first?.row == count - 1 && best.first?.score == 1,
                "similarity search considers rows beyond 50,000 and beyond 16-bit indices")
        #expect(index.similar(toRow: count - 1, limit: 5).allSatisfy { $0.row != count - 1 },
                "the selected sound is still excluded at the end of a large index")
    }

    @Test func mapHoverAndLassoReachTheLastRowsAndRespectFilters() {
        let xy = (0..<count).flatMap { [Float($0 % 400), Float($0 / 400)] }
        let grid = SpatialGrid(xy: xy)
        let point = SIMD2<Float>(399, 249)
        #expect(grid.nearest(to: point, within: 0.1) == count - 1)
        #expect(grid.nearest(to: point, within: 0.1, isIncluded: { $0 < count - 1 }) == nil)
        let outline: [SIMD2<Float>] = [[398.5, 248.5], [399.5, 248.5], [399.5, 249.5], [398.5, 249.5]]
        #expect(grid.rows(inPolygon: outline) == [count - 1], "lasso indices do not wrap after 65,535 dots")
        #expect(grid.rows(inPolygon: outline, isIncluded: { $0 < count - 1 }).isEmpty)
    }

    @Test func projectionAndClusteringKeepAllHundredThousandRows() throws {
        let chunkSize = 4096
        let model = try PCAModel.fit(dim: 4, maxComponents: 2) { body in
            for start in stride(from: 0, to: count, by: chunkSize) {
                let end = min(start + chunkSize, count)
                let rows = (start..<end).flatMap { i -> [Float] in [i % 2 == 0 ? 1 : -1, 0, 0, 0] }
                body(rows, end - start)
            }
        }
        let rows = (0..<count).flatMap { i -> [Float] in [i % 2 == 0 ? 1 : -1, 0, 0, 0] }
        let projected = model.project(rows, count: count)
        #expect(projected.count == count * model.k && projected.allSatisfy(\.isFinite))
        let clustered = KMeans.run(vectors: projected, count: count, dim: model.k, k: 2)
        #expect(clustered.assignments.count == count)
        #expect(clustered.assignments[0] == clustered.assignments[count - 2])
        #expect(clustered.assignments[1] == clustered.assignments[count - 1])
        #expect(clustered.assignments[0] != clustered.assignments[1], "opposite sounds stay in separate clusters")
    }
}
