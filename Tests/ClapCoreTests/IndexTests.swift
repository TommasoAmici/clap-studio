import Foundation
import Testing
@testable import ClapCore

/// Gaussian-ish blobs around well separated unit directions in `dim` dimensions.
func makeBlobs(clusters: Int, perCluster: Int, dim: Int, spread: Float = 0.05, seed: UInt64 = 7)
    -> (vectors: [Float], labels: [Int]) {
    var rng = SplitMix64(seed: seed)
    var centers: [[Float]] = []
    for _ in 0..<clusters {
        var c = (0..<dim).map { _ in rng.nextFloat() * 2 - 1 }
        let norm = sqrtf(c.reduce(0) { $0 + $1 * $1 })
        c = c.map { $0 / norm }
        centers.append(c)
    }
    var out: [Float] = [], labels: [Int] = []
    for (ci, c) in centers.enumerated() {
        for _ in 0..<perCluster {
            var v = c.map { $0 + (rng.nextFloat() - 0.5) * spread }
            let norm = sqrtf(v.reduce(0) { $0 + $1 * $1 })
            v = v.map { $0 / norm }
            out += v; labels.append(ci)
        }
    }
    return (out, labels)
}

@Suite struct IndexTests {
    @Test func pcaRecoversDominantAxis() throws {
        // Points stretched along axis (1,1,0,0)/sqrt2 in 4-D.
        var rng = SplitMix64(seed: 3)
        var rows: [Float] = []
        let n = 400
        for _ in 0..<n {
            let t = (rng.nextFloat() - 0.5) * 10, e = (rng.nextFloat() - 0.5) * 0.1
            rows += [t + e, t - e, e, -e]
        }
        let model = try PCAModel.fit(dim: 4, maxComponents: 2) { body in body(rows, n) }
        let c0 = Array(model.components[0..<4])
        let dot = abs((c0[0] + c0[1]) / sqrtf(2))
        #expect(dot > 0.99)
        let projected = model.project(rows, count: n)
        #expect(projected.count == n * model.k)
        let norm = (0..<model.k).reduce(Float(0)) { $0 + projected[$1] * projected[$1] }
        #expect(abs(norm - 1) < 1e-4)
    }

    @Test func topKMatchesBruteForce() {
        let (vectors, _) = makeBlobs(clusters: 5, perCluster: 40, dim: 16)
        let ids = (0..<200).map { Int64($0) }
        let index = VectorIndex(ids: ids, vectors: vectors, dim: 16)
        let result = index.similar(toRow: 17, limit: 10)
        let q = index.vector(row: 17)
        let brute = (0..<200).filter { $0 != 17 }
            .map { (row: $0, s: zip(index.vector(row: $0), q).reduce(Float(0)) { $0 + $1.0 * $1.1 }) }
            .sorted { $0.s > $1.s }.prefix(10).map(\.row)
        #expect(result.map(\.row) == Array(brute))
        #expect(!result.contains { $0.row == 17 })
    }

    @Test func kmeansFindsBlobsDeterministically() {
        let (vectors, labels) = makeBlobs(clusters: 4, perCluster: 50, dim: 12)
        let a = KMeans.run(vectors: vectors, count: 200, dim: 12, k: 4, seed: 1)
        let b = KMeans.run(vectors: vectors, count: 200, dim: 12, k: 4, seed: 1)
        #expect(a.assignments == b.assignments)
        // Every true blob maps to exactly one cluster.
        for blob in 0..<4 {
            let assigned = Set(zip(labels, a.assignments).filter { $0.0 == blob }.map(\.1))
            #expect(assigned.count == 1)
        }
        #expect(Set(a.assignments).count == 4)
    }
}

@Suite struct LayoutTests {
    @Test func layoutSeparatesClusters() {
        let (vectors, labels) = makeBlobs(clusters: 4, perCluster: 60, dim: 16, spread: 0.3)
        let n = labels.count
        let xy = MapLayout.layout(vectors: vectors, count: n, dim: 16, epochs: 200)
        #expect(xy.count == n * 2 && xy.allSatisfy { $0.isFinite })
        var within: Float = 0, between: Float = 0, wc = 0, bc = 0
        for i in stride(from: 0, to: n, by: 3) {
            for j in stride(from: 1, to: n, by: 3) where i != j {
                let d = hypotf(xy[i * 2] - xy[j * 2], xy[i * 2 + 1] - xy[j * 2 + 1])
                if labels[i] == labels[j] { within += d; wc += 1 } else { between += d; bc += 1 }
            }
        }
        #expect(within / Float(wc) < 0.6 * between / Float(bc))
    }

    @Test func layoutIsDeterministicEnoughToReproduceStructure() {
        let (vectors, labels) = makeBlobs(clusters: 3, perCluster: 30, dim: 8, spread: 0.2)
        let a = MapLayout.layout(vectors: vectors, count: labels.count, dim: 8, epochs: 50, seed: 5)
        #expect(a.count == labels.count * 2)
    }

    @Test func newPointLandsNearItsNeighbours() {
        let (vectors, labels) = makeBlobs(clusters: 3, perCluster: 40, dim: 8, spread: 0.2)
        let n = labels.count
        let xy = MapLayout.layout(vectors: vectors, count: n, dim: 8, epochs: 100)
        let index = VectorIndex(ids: (0..<n).map { Int64($0) }, vectors: vectors, dim: 8)
        let probe = Array(vectors[0..<8])
        let placed = MapLayout.place(vectors: probe, count: 1, dim: 8, among: index, coords: xy)
        let d = hypotf(placed[0] - xy[0], placed[1] - xy[1])
        #expect(d < 0.5)
    }

    @Test func tinyInputsDoNotCrash() {
        #expect(MapLayout.layout(vectors: [], count: 0, dim: 4).isEmpty)
        #expect(MapLayout.layout(vectors: [1, 0, 0, 0], count: 1, dim: 4).count == 2)
        let few = MapLayout.layout(vectors: (0..<20).map { Float($0 % 5) + 1 }, count: 5, dim: 4)
        #expect(few.count == 10 && few.allSatisfy { $0.isFinite })
    }
}

@Suite struct SpatialGridTests {
    @Test func nearestMatchesBruteForce() {
        var rng = SplitMix64(seed: 11)
        let n = 5000
        let xy = (0..<(n * 2)).map { _ in rng.nextFloat() * 2 - 1 }
        let grid = SpatialGrid(xy: xy)
        for _ in 0..<200 {
            let p = SIMD2<Float>(rng.nextFloat() * 2 - 1, rng.nextFloat() * 2 - 1)
            let r: Float = 0.03
            let expected = (0..<n).filter { hypotf(xy[$0 * 2] - p.x, xy[$0 * 2 + 1] - p.y) <= r }
                .min { hypotf(xy[$0 * 2] - p.x, xy[$0 * 2 + 1] - p.y) < hypotf(xy[$1 * 2] - p.x, xy[$1 * 2 + 1] - p.y) }
            #expect(grid.nearest(to: p, within: r) == expected)
        }
    }

    @Test func nearestSkipsFilteredOutPoints() {
        let grid = SpatialGrid(xy: [0, 0, 0.01, 0, 0.5, 0.5])
        #expect(grid.nearest(to: SIMD2(0, 0), within: 0.1) == 0)
        #expect(grid.nearest(to: SIMD2(0, 0), within: 0.1, isIncluded: { $0 != 0 }) == 1)
        #expect(grid.nearest(to: SIMD2(0, 0), within: 0.1, isIncluded: { $0 == 2 }) == nil)
    }

    @Test func emptyAndFarQueries() {
        #expect(SpatialGrid(xy: []).nearest(to: .zero, within: 1) == nil)
        let g = SpatialGrid(xy: [0, 0, 1, 1])
        #expect(g.nearest(to: SIMD2(50, 50), within: 0.5) == nil)
        #expect(g.nearest(to: SIMD2(0.9, 1.1), within: 0.5) == 1)
    }
}

@Suite struct HybridSearchTests {
    @Test func nameMatchesComeFirstThenClosestMeaning() {
        let scores: [Int64: Float] = [1: 0.1, 2: 0.9, 3: 0.5, 4: 0.7, 5: 0.2]
        let order = HybridSearch.rank(ids: [1, 2, 3, 4, 5], nameMatches: [1, 5], scores: scores, limit: 2)
        #expect(order == [5, 1, 2, 4], "named files (best score first), then the top 2 by meaning")
    }

    @Test func respectsCandidatesAndMissingScores() {
        let order = HybridSearch.rank(ids: [10, 11], nameMatches: [11], scores: [10: 0.3, 99: 1.0])
        #expect(order == [11, 10])
        #expect(HybridSearch.rank(ids: [7], nameMatches: [], scores: [:]).isEmpty)
    }
}

@Suite struct MapAxesTests {
    private func record(_ id: Int64, centroid: Double? = nil, loudness: Double? = nil, loop: Bool? = nil, bpm: Double? = nil) -> SampleRecord {
        var s = SampleRecord(id: id, rootID: 1, rootPath: "/", relPath: "s\(id).wav", name: "s\(id)", ext: "wav", duration: 1,
                             sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok, useCount: 0, lastUsed: nil, cueCount: 0)
        s.centroidHz = centroid; s.loudnessDB = loudness; s.isLoop = loop; s.bpm = bpm
        return s
    }

    @Test func layoutSpreadsByRankAndSkipsUnmeasured() {
        let samples: [SampleRecord?] = [record(1, centroid: 500, loudness: -30), record(2, centroid: 1000, loudness: -20),
                                         record(3, centroid: 100_000, loudness: -10), record(4, centroid: nil, loudness: -5), nil]
        let layout = MapAxes.layout(samples, x: .brightness, y: .loudness, extent: 10)
        #expect(layout.valid == [true, true, true, false, false])
        // The outlier at 100 kHz does not squash the others: ranks put the middle sample in the middle.
        #expect(abs(layout.xy[2]) < 0.5, "middle sample sits near the centre")
        #expect(layout.xy[0] < layout.xy[2] && layout.xy[2] < layout.xy[4])
        #expect(layout.xy[1] < layout.xy[3] && layout.xy[3] < layout.xy[5], "louder is higher")
    }

    @Test func tiesShareARankAndTempoNeedsALoop() {
        #expect(MapAxes.ranks([1, 2, 2, 3]) == [0, 0.5, 0.5, 1])
        #expect(MapProperty.tempo.value(of: record(1, loop: false, bpm: 120)) == nil)
        #expect(MapProperty.tempo.value(of: record(1, loop: true, bpm: 120)) == 120)
        #expect(MapAxes.bin(0.5, low: 0, high: 1, bins: 8) == 4)
        #expect(MapAxes.bin(1, low: 0, high: 1, bins: 8) == 7)
    }

    @Test func lassoSelectsPointsInsideAndHonoursTheFilter() {
        // A 10 x 10 lattice of points at integer positions.
        let xy: [Float] = (0..<100).flatMap { [Float($0 % 10), Float($0 / 10)] }
        let grid = SpatialGrid(xy: xy)
        let square: [SIMD2<Float>] = [[2.5, 2.5], [5.5, 2.5], [5.5, 5.5], [2.5, 5.5]]
        let rows = grid.rows(inPolygon: square)
        #expect(rows.count == 9)
        #expect(Set(rows) == Set((3...5).flatMap { y in (3...5).map { y * 10 + $0 } }))
        let triangle: [SIMD2<Float>] = [[0.5, 0.5], [4.5, 0.5], [0.5, 4.5]]
        #expect(grid.rows(inPolygon: triangle).count == 6, "points under the diagonal only")
        #expect(grid.rows(inPolygon: square, isIncluded: { $0 % 2 == 0 }).count == 3)
        #expect(grid.rows(inPolygon: [[0, 0], [1, 1]]).isEmpty, "not a polygon")
    }
}
