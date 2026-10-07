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
