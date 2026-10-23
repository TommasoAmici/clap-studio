import ClapCore
import Foundation

// Developer benchmark: how long do PCA, clustering, layout and search take at library scale?
// Usage: scripts/bench.sh [sampleCount] [embeddingDim]
let n = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 50_000 : 50_000
let dim = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 2048 : 2048

func time<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    let start = Date()
    let value = try body()
    print(String(format: "%-28@ %7.2f s", label as NSString, Date().timeIntervalSince(start)))
    return value
}

var rng = SplitMix64(seed: 1)
let centers = (0..<40).map { _ in (0..<dim).map { _ in rng.nextFloat() * 2 - 1 } }
print("Generating \(n) x \(dim) embeddings")
var data = [Float](repeating: 0, count: n * dim)
for i in 0..<n {
    let c = centers[i % centers.count]
    var norm: Float = 0
    for j in 0..<dim { let v = c[j] + (rng.nextFloat() - 0.5) * 1.2; data[i * dim + j] = v; norm += v * v }
    norm = norm.squareRoot()
    for j in 0..<dim { data[i * dim + j] /= norm }
}

let chunk = 4096
let pca = try time("PCA fit (128 comps)") {
    try PCAModel.fit(dim: dim, maxComponents: 128) { body in
        var start = 0
        while start < n {
            let rows = min(chunk, n - start)
            body(Array(data[(start * dim)..<((start + rows) * dim)]), rows)
            start += rows
        }
    }
}
var projected = [Float]()
time("Projection") {
    var start = 0
    while start < n {
        let rows = min(chunk, n - start)
        projected += pca.project(Array(data[(start * dim)..<((start + rows) * dim)]), count: rows)
        start += rows
    }
}
let km = time("k-means (k=16)") { KMeans.run(vectors: projected, count: n, dim: pca.k, k: 16) }
let xy = time("2D layout") { MapLayout.layout(vectors: projected, count: n, dim: pca.k) }
let index = VectorIndex(ids: (0..<n).map { Int64($0) }, vectors: projected, dim: pca.k)
time("100 similarity queries") { for q in 0..<100 { _ = index.similar(toRow: q * 7 % n, limit: 50) } }
let grid = time("Hit-test grid build") { SpatialGrid(xy: xy) }
time("100k hover lookups") { for i in 0..<100_000 { _ = grid.nearest(to: SIMD2(Float(i % 200) / 100 - 1, Float(i % 137) / 70 - 1), within: 0.01) } }
print("clusters: \(km.k), points: \(xy.count / 2)")
