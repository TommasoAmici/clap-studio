import Foundation

/// Files that are copies of each other. Nothing is changed; the caller decides what to do with them.
public struct DuplicateGroup: Identifiable, Sendable, Equatable {
    public let id: Int
    /// Best copy first: the one worth keeping.
    public let ids: [Int64]
    public init(id: Int, ids: [Int64]) { self.id = id; self.ids = ids }
    public var keeper: Int64 { ids[0] }
    public var extras: [Int64] { Array(ids.dropFirst()) }
}

/// Finds files that are copies of each other: same size and same start and end bytes (the file fingerprint).
/// Files that only sound alike, such as re-exports or other formats, are not flagged.
public enum DuplicateFinder {
    public static func find(store: LibraryStore, samples: [SampleRecord]) -> [DuplicateGroup] {
        let candidates = samples.filter { $0.status == .ok && !$0.hidden }
        let fingerprints = store.fingerprints()

        var byFingerprint: [String: [SampleRecord]] = [:]
        for s in candidates {
            guard let fp = fingerprints[s.id] else { continue }
            byFingerprint[fp, default: []].append(s)
        }

        var groups = byFingerprint.values.filter { $0.count > 1 }.map { copies in
            copies.sorted(by: better).map(\.id)
        }
        // Biggest groups first; ties keep a stable order.
        groups.sort { ($0.count, $1[0]) > ($1.count, $0[0]) }
        return groups.enumerated().map { DuplicateGroup(id: $0.offset, ids: $0.element) }
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
}
