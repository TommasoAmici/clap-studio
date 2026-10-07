import Accelerate
import Foundation

public struct Neighbor: Sendable, Hashable {
    public let row: Int
    public let score: Float
}

/// In-memory cosine index over L2-normalised vectors. Brute force with one
/// matrix-vector product, which takes a few milliseconds even at 50k rows.
public final class VectorIndex: @unchecked Sendable {
    public let ids: [Int64]
    public let dim: Int
    public let vectors: [Float]
    private let rowForID: [Int64: Int]

    public var count: Int { ids.count }

    public init(ids: [Int64], vectors: [Float], dim: Int) {
        precondition(vectors.count == ids.count * dim)
        self.ids = ids; self.vectors = vectors; self.dim = dim
        rowForID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
    }

    public func row(forID id: Int64) -> Int? { rowForID[id] }

    public func vector(row: Int) -> [Float] { Array(vectors[(row * dim)..<((row + 1) * dim)]) }

    /// Most similar rows to `row`, best first, excluding itself.
    public func similar(toRow row: Int, limit: Int) -> [Neighbor] {
        topK(query: vector(row: row), limit: limit, excluding: row)
    }

    public func topK(query: [Float], limit: Int, excluding: Int? = nil) -> [Neighbor] {
        let n = count
        guard n > 0, limit > 0, query.count == dim else { return [] }
        var scores = [Float](repeating: 0, count: n)
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(dim), 1, vectors, Int32(dim), query, 1, 0, &scores, 1)
        return Self.select(scores: scores, limit: limit, excluding: excluding)
    }

    static func select(scores: [Float], limit: Int, excluding: Int?) -> [Neighbor] {
        var best: [Neighbor] = []
        best.reserveCapacity(limit + 1)
        var floor = -Float.infinity
        for (i, s) in scores.enumerated() where i != excluding {
            if best.count < limit {
                best.append(Neighbor(row: i, score: s))
                if best.count == limit { floor = best.map(\.score).min() ?? -.infinity }
            } else if s > floor {
                if let minIdx = best.indices.min(by: { best[$0].score < best[$1].score }) {
                    best[minIdx] = Neighbor(row: i, score: s)
                    floor = best.map(\.score).min() ?? -.infinity
                }
            }
        }
        return best.sorted { $0.score > $1.score }
    }
}
