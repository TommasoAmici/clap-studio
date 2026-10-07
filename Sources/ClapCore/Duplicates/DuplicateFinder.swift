import Accelerate
import Foundation

public struct DuplicateGroup: Identifiable, Sendable, Equatable {
    public let id: Int
    /// Best copy first: the one worth keeping.
    public let ids: [Int64]
    /// True when the files are byte-for-byte alike as far as the fingerprint can tell;
    /// false when they only sound the same (re-exports, different formats, tiny edits).
    public let identical: Bool
    public var keeper: Int64 { ids[0] }
    public var extras: [Int64] { Array(ids.dropFirst()) }
}

/// Finds files that are copies of each other: same fingerprint, or near-identical CLAP embeddings
/// with the same length. Nothing is changed; the caller decides what to hide.
public enum DuplicateFinder {
    public static let defaultSimilarity: Float = 0.985
    static let durationTolerance = 0.03

    public static func find(store: LibraryStore, samples: [SampleRecord], modelVersion: String,
                            similarity: Float = defaultSimilarity,
                            isCancelled: () -> Bool = { false }) throws -> [DuplicateGroup] {
        let candidates = samples.filter { $0.status == .ok && !$0.hidden }
        var byID: [Int64: SampleRecord] = [:]
        for s in candidates { byID[s.id] = s }
        var sets = UnionFind(Array(byID.keys))
        let fingerprints = store.fingerprints()

        // Identical files.
        var firstWith: [String: Int64] = [:]
        for s in candidates.sorted(by: { $0.id < $1.id }) {
            guard let fp = fingerprints[s.id] else { continue }
            if let other = firstWith[fp] { sets.union(s.id, other) } else { firstWith[fp] = s.id }
        }

        // Sounds that match.
        var ids: [Int64] = [], flat: [Float] = []
        try store.forEachEmbeddingChunk(modelVersion: modelVersion) { chunkIDs, chunk, _ in
            for (i, id) in chunkIDs.enumerated() where byID[id] != nil {
                ids.append(id)
                flat += chunk[(i * 512)..<((i + 1) * 512)]
            }
        }
        try nearPairs(ids: ids, flat: flat, dim: 512, threshold: similarity, isCancelled: isCancelled) { a, b in
            guard let x = byID[a], let y = byID[b] else { return }
            let longest = max(x.duration, y.duration, 0.001)
            if abs(x.duration - y.duration) / longest <= durationTolerance { sets.union(a, b) }
        }

        var members: [Int64: [Int64]] = [:]
        for id in byID.keys { members[sets.find(id), default: []].append(id) }
        var groups = members.values.filter { $0.count > 1 }.map { group -> ([Int64], Bool) in
            let ranked = group.sorted { better(byID[$0]!, byID[$1]!) }
            let prints = Set(group.map { fingerprints[$0] ?? "" })
            return (ranked, prints.count == 1 && prints.first != "")
        }
        groups.sort { ($0.0.count, $1.0[0]) > ($1.0.count, $0.0[0]) }
        return groups.enumerated().map { DuplicateGroup(id: $0.offset, ids: $0.element.0, identical: $0.element.1) }
    }

    /// Which copy to keep: the one already in use, then the highest quality, then the shortest path.
    static func better(_ a: SampleRecord, _ b: SampleRecord) -> Bool {
        if a.useCount != b.useCount { return a.useCount > b.useCount }
        if a.favorite != b.favorite { return a.favorite }
        if a.sampleRate != b.sampleRate { return a.sampleRate > b.sampleRate }
        if a.size != b.size { return a.size > b.size }
        if a.relPath.count != b.relPath.count { return a.relPath.count < b.relPath.count }
        return a.id < b.id
    }

    /// Calls `body` for every pair of rows whose cosine similarity reaches `threshold`.
    /// Works in blocks so 50k samples need a few matrix products, not 50k vector products.
    static func nearPairs(ids: [Int64], flat: [Float], dim: Int, threshold: Float,
                          isCancelled: () -> Bool, _ body: (Int64, Int64) -> Void) throws {
        let n = ids.count, block = 256
        guard n > 1 else { return }
        var scores = [Float](repeating: 0, count: block * n)
        var start = 0
        while start < n {
            if isCancelled() { return }
            let rows = min(block, n - start)
            flat.withUnsafeBufferPointer { all in
                cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(rows), Int32(n), Int32(dim), 1,
                            all.baseAddress! + start * dim, Int32(dim), all.baseAddress!, Int32(dim), 0, &scores, Int32(n))
            }
            for r in 0..<rows {
                let i = start + r
                for j in (i + 1)..<max(n, i + 1) where scores[r * n + j] >= threshold { body(ids[i], ids[j]) }
            }
            start += rows
        }
    }
}

struct UnionFind {
    private var parent: [Int64: Int64]
    init(_ ids: [Int64]) { parent = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) }) }

    mutating func find(_ x: Int64) -> Int64 {
        var root = x
        while let p = parent[root], p != root { root = p }
        var node = x
        while let p = parent[node], p != root { parent[node] = root; node = p }
        return root
    }

    mutating func union(_ a: Int64, _ b: Int64) {
        let (ra, rb) = (find(a), find(b))
        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }
}
