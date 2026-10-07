import Accelerate
import Foundation

/// UMAP-style 2D layout: cosine kNN graph -> fuzzy edge weights -> parallel SGD.
/// Output coordinates are interleaved (x0, y0, x1, y1, ...), centred and scaled
/// so that most points fall inside the unit disc.
public enum MapLayout {
    struct Edges {
        var head: [Int32] = [], tail: [Int32] = [], weight: [Float] = []
    }

    public static func layout(vectors: [Float], count n: Int, dim: Int, neighbors: Int = 15,
                              epochs: Int? = nil, seed: UInt64 = 42) -> [Float] {
        if n == 0 { return [] }
        if n < 4 { return (0..<n).flatMap { [Float($0) / Float(max(1, n - 1)) * 2 - 1, 0] } }

        let k = min(neighbors, n - 1)
        let (nn, dist) = knn(vectors: vectors, n: n, dim: dim, k: k)
        let edges = fuzzyEdges(nn: nn, dist: dist, n: n, k: k)
        let total = epochs ?? (n <= 2_000 ? 500 : (n <= 10_000 ? 300 : 200))
        var y = initialPositions(vectors: vectors, n: n, dim: dim, seed: seed)
        optimize(&y, edges: edges, n: n, epochs: total, seed: seed)
        normalize(&y, n: n)
        return y
    }

    // MARK: kNN

    static func knn(vectors: [Float], n: Int, dim: Int, k: Int) -> (idx: [Int32], dist: [Float]) {
        var idx = [Int32](repeating: 0, count: n * k)
        var dist = [Float](repeating: 0, count: n * k)
        let block = 256
        var scores = [Float](repeating: 0, count: min(block, n) * n)

        var start = 0
        while start < n {
            let rows = min(block, n - start)
            vectors.withUnsafeBufferPointer { v in
                cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(rows), Int32(n), Int32(dim),
                            1, v.baseAddress! + start * dim, Int32(dim), v.baseAddress!, Int32(dim),
                            0, &scores, Int32(n))
            }
            scores.withUnsafeBufferPointer { sc in
                idx.withUnsafeMutableBufferPointer { out in
                    dist.withUnsafeMutableBufferPointer { dOut in
                        let base = start
                        let outIdx = out.baseAddress!, outDist = dOut.baseAddress!
                        DispatchQueue.concurrentPerform(iterations: rows) { r in
                            let row = sc.baseAddress! + r * n
                            var bestI = [Int32](repeating: -1, count: k)
                            var bestS = [Float](repeating: -.infinity, count: k)
                            var floor = -Float.infinity
                            for j in 0..<n where j != base + r {
                                let s = row[j]
                                if s > floor {
                                    var m = 0
                                    for t in 1..<k where bestS[t] < bestS[m] { m = t }
                                    bestS[m] = s; bestI[m] = Int32(j)
                                    floor = bestS.min() ?? -.infinity
                                }
                            }
                            let order = (0..<k).sorted { bestS[$0] > bestS[$1] }
                            for (slot, o) in order.enumerated() {
                                outIdx[(base + r) * k + slot] = bestI[o]
                                outDist[(base + r) * k + slot] = max(0, 1 - bestS[o])
                            }
                        }
                    }
                }
            }
            start += rows
        }
        return (idx, dist)
    }

    // MARK: fuzzy simplicial set

    static func fuzzyEdges(nn: [Int32], dist: [Float], n: Int, k: Int) -> Edges {
        var weights = [UInt64: Float](minimumCapacity: n * k)
        let target = log2(Float(k))
        for i in 0..<n {
            let d = Array(dist[(i * k)..<((i + 1) * k)])
            let rho = d.first(where: { $0 > 0 }) ?? 0
            var lo: Float = 1e-6, hi: Float = 1e3, sigma: Float = 1
            for _ in 0..<48 {
                sigma = (lo + hi) / 2
                let sum = d.reduce(Float(0)) { $0 + expf(-max(0, $1 - rho) / sigma) }
                if sum > target { hi = sigma } else { lo = sigma }
            }
            for j in 0..<k {
                let other = Int(nn[i * k + j])
                let w = expf(-max(0, d[j] - rho) / sigma)
                let key = UInt64(min(i, other)) << 32 | UInt64(max(i, other))
                if let existing = weights[key] { weights[key] = existing + w - existing * w }
                else { weights[key] = w }
            }
        }
        var edges = Edges()
        edges.head.reserveCapacity(weights.count)
        for (key, w) in weights {
            edges.head.append(Int32(key >> 32)); edges.tail.append(Int32(key & 0xFFFF_FFFF)); edges.weight.append(w)
        }
        return edges
    }

    // MARK: optimisation

    static func initialPositions(vectors: [Float], n: Int, dim: Int, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        var y = [Float](repeating: 0, count: n * 2)
        guard dim >= 2 else {
            for i in 0..<(n * 2) { y[i] = (rng.nextFloat() - 0.5) * 20 }
            return y
        }
        for axis in 0..<2 {
            var mean: Float = 0, sq: Float = 0
            for i in 0..<n { mean += vectors[i * dim + axis] }
            mean /= Float(n)
            for i in 0..<n { let d = vectors[i * dim + axis] - mean; sq += d * d }
            let std = max(sqrtf(sq / Float(n)), 1e-6)
            for i in 0..<n { y[i * 2 + axis] = (vectors[i * dim + axis] - mean) / std * 3 + (rng.nextFloat() - 0.5) * 0.01 }
        }
        return y
    }

    static func optimize(_ y: inout [Float], edges: Edges, n: Int, epochs: Int, seed: UInt64) {
        guard !edges.weight.isEmpty else { return }
        let a: Float = 1.577, b: Float = 0.895
        let maxW = edges.weight.max() ?? 1
        let keep = (0..<edges.weight.count).filter { edges.weight[$0] >= maxW / Float(epochs) }
        let head = keep.map { edges.head[$0] }, tail = keep.map { edges.tail[$0] }
        let prob = keep.map { edges.weight[$0] / maxW }
        let shards = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 16))
        let negatives = 5
        let m = head.count

        y.withUnsafeMutableBufferPointer { yp in
            let pos = yp.baseAddress!
            for epoch in 0..<epochs {
                let alpha = 1 - Float(epoch) / Float(epochs)
                DispatchQueue.concurrentPerform(iterations: shards) { shard in
                    var rng = SplitMix64(seed: seed &+ UInt64(epoch) &* 7919 &+ UInt64(shard) &* 104_729)
                    let lo = m * shard / shards, hi = m * (shard + 1) / shards
                    for e in lo..<hi {
                        if rng.nextFloat() > prob[e] { continue }
                        let i = Int(head[e]), j = Int(tail[e])
                        var dx = pos[i * 2] - pos[j * 2], dy = pos[i * 2 + 1] - pos[j * 2 + 1]
                        var d2 = dx * dx + dy * dy
                        if d2 > 0 {
                            let coeff = -2 * a * b * powf(d2, b - 1) / (a * powf(d2, b) + 1)
                            let gx = clip(coeff * dx) * alpha, gy = clip(coeff * dy) * alpha
                            pos[i * 2] += gx; pos[i * 2 + 1] += gy
                            pos[j * 2] -= gx; pos[j * 2 + 1] -= gy
                        }
                        for _ in 0..<negatives {
                            let r = Int(rng.next() % UInt64(n))
                            if r == i { continue }
                            dx = pos[i * 2] - pos[r * 2]; dy = pos[i * 2 + 1] - pos[r * 2 + 1]
                            d2 = dx * dx + dy * dy
                            if d2 > 0 {
                                let coeff = 2 * b / ((0.001 + d2) * (a * powf(d2, b) + 1))
                                pos[i * 2] += clip(coeff * dx) * alpha
                                pos[i * 2 + 1] += clip(coeff * dy) * alpha
                            } else {
                                pos[i * 2] += 4 * alpha
                            }
                        }
                    }
                }
            }
        }
    }

    @inline(__always) private static func clip(_ x: Float) -> Float { max(-4, min(4, x)) }

    /// Centre on the median and scale so the 98th-percentile radius is 1.
    static func normalize(_ y: inout [Float], n: Int) {
        func median(_ axis: Int) -> Float {
            let s = (0..<n).map { y[$0 * 2 + axis] }.sorted()
            return s[n / 2]
        }
        let cx = median(0), cy = median(1)
        for i in 0..<n { y[i * 2] -= cx; y[i * 2 + 1] -= cy }
        let radii = (0..<n).map { hypotf(y[$0 * 2], y[$0 * 2 + 1]) }.sorted()
        let r = max(radii[min(n - 1, Int(Float(n) * 0.98))], 1e-6)
        for i in 0..<(n * 2) { y[i] /= r }
    }

    // MARK: incremental placement

    /// Places new vectors near their nearest already-placed neighbours, so a handful
    /// of new samples never makes existing dots jump.
    public static func place(vectors: [Float], count m: Int, dim: Int, among index: VectorIndex,
                             coords: [Float], seed: UInt64 = 1) -> [Float] {
        var rng = SplitMix64(seed: seed)
        var out = [Float](repeating: 0, count: m * 2)
        for i in 0..<m {
            let q = Array(vectors[(i * dim)..<((i + 1) * dim)])
            let near = index.topK(query: q, limit: 5)
            var wx: Float = 0, wy: Float = 0, wsum: Float = 0
            for nb in near {
                let w = powf(max(nb.score, 0), 3) + 1e-4
                wx += coords[nb.row * 2] * w; wy += coords[nb.row * 2 + 1] * w; wsum += w
            }
            if wsum > 0 { out[i * 2] = wx / wsum; out[i * 2 + 1] = wy / wsum }
            out[i * 2] += (rng.nextFloat() - 0.5) * 0.02
            out[i * 2 + 1] += (rng.nextFloat() - 0.5) * 0.02
        }
        return out
    }
}
