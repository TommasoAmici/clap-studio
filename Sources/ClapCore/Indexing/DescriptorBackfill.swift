import Foundation

/// Measures descriptors for samples that were indexed before they existed (or after an analyser upgrade),
/// without touching embeddings. New files get their descriptors during normal indexing.
public final class DescriptorBackfill: @unchecked Sendable {
    private let store: LibraryStore
    private let workers: Int
    private let batchSize: Int

    public init(store: LibraryStore,
                workers: Int = min(max(2, ProcessInfo.processInfo.activeProcessorCount - 2), 8),
                batchSize: Int = 200) {
        self.store = store
        self.workers = workers
        self.batchSize = batchSize
    }

    @discardableResult
    public func run(onProgress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void,
                    isCancelled: @escaping @Sendable () -> Bool = { false }) async -> Int {
        let total = store.descriptorBacklog()
        var done = 0
        onProgress(0, total)
        while !isCancelled() {
            let jobs = store.descriptorJobs(limit: batchSize)
            if jobs.isEmpty { break }
            let results = await analyze(jobs, isCancelled: isCancelled)
            do { try store.saveDescriptors(results) } catch { break }
            done += results.count
            onProgress(done, total)
            if results.count < jobs.count { break }       // cancelled mid-batch
        }
        return done
    }

    private func analyze(_ jobs: [IndexJob], isCancelled: @escaping @Sendable () -> Bool) async -> [(id: Int64, descriptors: SoundDescriptors?)] {
        let queue = Queue(jobs)
        return await withTaskGroup(of: [(Int64, SoundDescriptors?)].self) { group in
            for _ in 0..<min(workers, jobs.count) {
                group.addTask {
                    let analyzer = DescriptorAnalyzer()
                    var local: [(Int64, SoundDescriptors?)] = []
                    while !isCancelled(), let job = queue.next() {
                        local.append((job.id, Self.measure(job, analyzer)))
                    }
                    return local
                }
            }
            var all: [(id: Int64, descriptors: SoundDescriptors?)] = []
            for await part in group { all += part.map { (id: $0.0, descriptors: $0.1) } }
            return all
        }
    }

    static func measure(_ job: IndexJob, _ analyzer: DescriptorAnalyzer) -> SoundDescriptors? {
        guard let audio = try? AudioDecoder.decodeForAnalysis(url: job.url, maxSeconds: DescriptorAnalyzer.analysisSeconds,
                                                              sampleRate: 32_000) else { return nil }
        return analyzer.analyze(samples: audio.samples, sampleRate: 32_000, fileDuration: audio.duration)
    }

    private final class Queue: @unchecked Sendable {
        private var jobs: [IndexJob]
        private var index = 0
        private let lock = NSLock()
        init(_ jobs: [IndexJob]) { self.jobs = jobs }
        func next() -> IndexJob? {
            lock.lock(); defer { lock.unlock() }
            guard index < jobs.count else { return nil }
            defer { index += 1 }
            return jobs[index]
        }
    }
}
