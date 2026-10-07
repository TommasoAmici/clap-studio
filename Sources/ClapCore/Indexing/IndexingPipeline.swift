import Foundation

public struct IndexProgress: Sendable {
    public var total: Int
    public var done: Int
    public var failed: Int
    public var currentName: String
    public var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }
}

/// Embeds every pending sample and commits results in small batches, so quitting
/// (or crashing) mid-run loses almost nothing and the next launch resumes.
public final class IndexingPipeline: @unchecked Sendable {
    private let store: LibraryStore
    private let embedder: EmbeddingProvider
    private let workers: Int
    private let batchSize: Int

    public init(store: LibraryStore, embedder: EmbeddingProvider,
                workers: Int = min(max(2, ProcessInfo.processInfo.activeProcessorCount - 2), 8),
                batchSize: Int = 200) {
        self.store = store
        self.embedder = embedder
        self.workers = workers
        self.batchSize = batchSize
    }

    /// Returns the number of samples processed successfully.
    @discardableResult
    public func run(onProgress: @escaping @Sendable (IndexProgress) -> Void,
                    isCancelled: @escaping @Sendable () -> Bool = { false }) async -> Int {
        var progress = IndexProgress(total: store.pendingCount(), done: 0, failed: 0, currentName: "")
        var succeeded = 0
        onProgress(progress)

        while !isCancelled() {
            let jobs = store.pendingJobs(limit: batchSize)
            if jobs.isEmpty { break }
            let base = progress
            let live = LiveCounter()
            let results = await process(jobs, isCancelled: isCancelled) { name in
                let finished = live.increment()
                onProgress(IndexProgress(total: base.total, done: base.done + finished,
                                         failed: base.failed, currentName: name))
            }
            do { try store.save(results: results) } catch { break }
            for r in results {
                progress.done += 1
                if case .failure = r { progress.failed += 1 } else { succeeded += 1 }
            }
            onProgress(progress)
            if results.count < jobs.count { break }   // cancelled mid-batch
        }
        return succeeded
    }

    private func process(_ jobs: [IndexJob], isCancelled: @escaping @Sendable () -> Bool,
                         onItemDone: @escaping @Sendable (String) -> Void) async -> [IndexResult] {
        let queue = JobQueue(jobs)
        let embedder = self.embedder
        return await withTaskGroup(of: [IndexResult].self) { group in
            for _ in 0..<min(workers, jobs.count) {
                group.addTask {
                    let extractor = LogMelExtractor()
                    var local: [IndexResult] = []
                    while !isCancelled(), let job = queue.next() {
                        local.append(Self.embedOne(job, extractor: extractor, embedder: embedder))
                        onItemDone(job.url.lastPathComponent)
                    }
                    return local
                }
            }
            var all: [IndexResult] = []
            for await part in group { all += part }
            return all
        }
    }

    static func embedOne(_ job: IndexJob, extractor: LogMelExtractor, embedder: EmbeddingProvider) -> IndexResult {
        do {
            let audio = try AudioDecoder.decodeForAnalysis(url: job.url)
            let mel = extractor.extract(signal: audio.samples)
            let vector = try embedder.embed(mel)
            return .success(id: job.id, duration: audio.duration, sampleRate: audio.sampleRate,
                            channels: audio.channels, embedding: vector,
                            fingerprint: FileFingerprint.compute(url: job.url), modelVersion: embedder.version)
        } catch {
            return .failure(id: job.id, message: String(describing: error))
        }
    }
}

private final class JobQueue: @unchecked Sendable {
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

private final class LiveCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
