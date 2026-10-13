import Foundation

/// Looks through the library's files for what they carry: places (so recordings from a phone or recorder with GPS
/// appear on the map without anyone typing a location) and descriptive metadata (titles, keywords, UCS names).
public final class FileInfoBackfill: @unchecked Sendable {
    private let store: LibraryStore
    private let batchSize: Int

    public init(store: LibraryStore, batchSize: Int = 400) { self.store = store; self.batchSize = batchSize }

    /// Returns the samples that got a place.
    @discardableResult
    public func run(onProgress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void,
                    isCancelled: @escaping @Sendable () -> Bool = { false }) async -> [Int64] {
        let total = store.locationBacklog()
        var done = 0, placed: [Int64] = []
        onProgress(0, total)
        while !isCancelled() {
            let jobs = store.locationJobs(limit: batchSize)
            if jobs.isEmpty { break }
            var found: [(id: Int64, point: GeoPoint?)] = []
            var described: [(id: Int64, meta: FileMetadata)] = []
            @Sendable func read(_ job: IndexJob) async -> (Int64, GeoPoint?, FileMetadata) {
                (job.id, await LocationReader.read(url: job.url), FileMetadataReader.read(url: job.url))
            }
            await withTaskGroup(of: (Int64, GeoPoint?, FileMetadata).self) { group in
                var iterator = jobs.makeIterator()
                for _ in 0..<8 { if let job = iterator.next() { group.addTask { await read(job) } } }
                for await result in group {
                    found.append((result.0, result.1)); described.append((result.0, result.2))
                    if !isCancelled(), let job = iterator.next() { group.addTask { await read(job) } }
                }
            }
            // Files are marked as looked at only when both have been stored, or they would never be read again.
            guard (try? store.saveFileMetadata(described)) != nil, let saved = try? store.saveFileLocations(found) else { break }
            placed += saved
            done += found.count
            onProgress(done, total)
            if found.count < jobs.count { break }          // cancelled mid-batch
        }
        return placed
    }
}
