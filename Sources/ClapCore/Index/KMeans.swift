import Accelerate
import Foundation

public struct KMeansResult: Sendable {
    public let k: Int
    public let dim: Int
    /// k x dim, L2-normalised.
    public let centroids: [Float]
    public let assignments: [Int32]
}

/// Spherical k-means (cosine) with k-means++ seeding. Deterministic for a given seed.
public enum KMeans {
    public static func run(vectors: [Float], count n: Int, dim: Int, k requestedK: Int,
                           iterations: Int = 30, seed: UInt64 = 42) -> KMeansResult {
        let k = max(1, min(requestedK, n))
        var rng = SplitMix64(seed: seed)
        var centroids = seedCentroids(vectors, n, dim, k, &rng)
        var assignments = [Int32](repeating: -1, count: n)

        for _ in 0..<iterations {
            let next = assign(vectors: vectors, count: n, dim: dim, centroids: centroids, k: k)
            let changed = next != assignments
            assignments = next
            centroids = recompute(vectors, n, dim, k, assignments, previous: centroids, &rng)
            if !changed { break }
        }
        return KMeansResult(k: k, dim: dim, centroids: centroids, assignments: assignments)
    }

    public static func assign(vectors: [Float], count n: Int, dim: Int, centroids: [Float], k: Int) -> [Int32] {
        guard n > 0 else { return [] }
        var scores = [Float](repeating: 0, count: n * k)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(n), Int32(k), Int32(dim),
                    1, vectors, Int32(dim), centroids, Int32(dim), 0, &scores, Int32(k))
        var out = [Int32](repeating: 0, count: n)
        for i in 0..<n {
            var best = 0
            var bestScore = scores[i * k]
            for c in 1..<max(k, 1) where scores[i * k + c] > bestScore { best = c; bestScore = scores[i * k + c] }
            out[i] = Int32(best)
        }
        return out
    }

    private static func seedCentroids(_ v: [Float], _ n: Int, _ dim: Int, _ k: Int,
                                      _ rng: inout SplitMix64) -> [Float] {
        var centroids = [Float](repeating: 0, count: k * dim)
        var bestSim = [Float](repeating: -1, count: n)   // similarity to nearest chosen centroid
        var first = Int(rng.next() % UInt64(n))
        for c in 0..<k {
            if c > 0 {
                var total: Double = 0
                var weights = [Double](repeating: 0, count: n)
                for i in 0..<n { let d = Double(max(0, 1 - bestSim[i])); weights[i] = d * d; total += weights[i] }
                if total <= 0 { first = Int(rng.next() % UInt64(n)) } else {
                    var target = Double(rng.nextFloat()) * total
                    first = n - 1
                    for i in 0..<n { target -= weights[i]; if target <= 0 { first = i; break } }
                }
            }
            for j in 0..<dim { centroids[c * dim + j] = v[first * dim + j] }
            var sims = [Float](repeating: 0, count: n)
            let q = Array(v[(first * dim)..<((first + 1) * dim)])
            cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(dim), 1, v, Int32(dim), q, 1, 0, &sims, 1)
            for i in 0..<n where sims[i] > bestSim[i] { bestSim[i] = sims[i] }
        }
        return centroids
    }

    private static func recompute(_ v: [Float], _ n: Int, _ dim: Int, _ k: Int, _ a: [Int32],
                                  previous: [Float], _ rng: inout SplitMix64) -> [Float] {
        var sums = [Float](repeating: 0, count: k * dim)
        var sizes = [Int](repeating: 0, count: k)
        for i in 0..<n {
            let c = Int(a[i]); sizes[c] += 1
            v.withUnsafeBufferPointer { src in
                sums.withUnsafeMutableBufferPointer { dst in
                    vDSP_vadd(dst.baseAddress! + c * dim, 1, src.baseAddress! + i * dim, 1,
                              dst.baseAddress! + c * dim, 1, vDSP_Length(dim))
                }
            }
        }
        for c in 0..<k {
            if sizes[c] == 0 {   // reseed an empty cluster on a random point
                let i = Int(rng.next() % UInt64(n))
                for j in 0..<dim { sums[c * dim + j] = v[i * dim + j] }
            }
            var norm: Float = 0
            sums.withUnsafeBufferPointer { vDSP_svesq($0.baseAddress! + c * dim, 1, &norm, vDSP_Length(dim)) }
            norm = sqrtf(norm)
            if norm > 1e-12 { for j in 0..<dim { sums[c * dim + j] /= norm } }
            else { for j in 0..<dim { sums[c * dim + j] = previous[c * dim + j] } }
        }
        return sums
    }
}
