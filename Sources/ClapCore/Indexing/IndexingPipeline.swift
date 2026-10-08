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
                    let extractor = LogMelExtractor(config: embedder.frontEnd)
                    let analyzer = DescriptorAnalyzer()
                    var local: [IndexResult] = []
                    while !isCancelled(), let job = queue.next() {
                        guard let result = Self.embedOne(job, extractor: extractor, analyzer: analyzer,
                                                         embedder: embedder, isCancelled: isCancelled) else { break }
                        local.append(result)
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

    /// Nil when cancelled part-way through a long file: nothing is saved and the file stays pending.
    static func embedOne(_ job: IndexJob, extractor: LogMelExtractor, analyzer: DescriptorAnalyzer,
                         embedder: EmbeddingProvider, isCancelled: @Sendable () -> Bool = { false }) -> IndexResult? {
        do {
            let info = try AudioDecoder.fileInfo(url: job.url)
            if FieldRecording.isFieldRecording(duration: info.duration) {
                return try embedFieldRecording(job, info: info, extractor: extractor, analyzer: analyzer,
                                               embedder: embedder, isCancelled: isCancelled)
            }
            let input = try EmbeddingInput.load(url: job.url, frontEnd: embedder.frontEnd, analyzer: analyzer)
            let vector = try embedder.embed(extractor.extract(signal: input.signal))
            return .success(id: job.id, duration: input.audio.duration, sampleRate: input.audio.sampleRate,
                            channels: input.audio.channels, embedding: vector,
                            fingerprint: FileFingerprint.compute(url: job.url), modelVersion: embedder.version,
                            cues: CueFileReader.read(url: job.url), descriptors: input.descriptors)
        } catch {
            return .failure(id: job.id, message: String(describing: error))
        }
    }

    /// Long recordings: split at silences, embed each audible segment on its own, and store the composite.
    private static func embedFieldRecording(_ job: IndexJob, info: (duration: Double, sampleRate: Double, channels: Int),
                                            extractor: LogMelExtractor, analyzer: DescriptorAnalyzer,
                                            embedder: EmbeddingProvider, isCancelled: @Sendable () -> Bool) throws -> IndexResult? {
        let rate = Double(embedder.frontEnd.sampleRate)
        let envelope = try AudioDecoder.loudnessEnvelope(url: job.url)
        var spans = RecordingSegmenter.segments(envelopeDB: envelope.levelsDB, hop: envelope.hop, duration: envelope.duration)
        // A recording that is silent throughout still gets one segment, so it can be found and played.
        if spans.isEmpty { spans = [TimeSpan(start: 0, end: min(envelope.duration, RecordingSegmenter.maximumSegmentSeconds))] }

        var segments: [SegmentEmbedding] = []
        var parts: [(descriptors: SoundDescriptors, seconds: Double)] = []
        for span in spans {
            if isCancelled() { return nil }
            let raw = try AudioDecoder.decode(url: job.url, start: span.start, seconds: span.length, sampleRate: rate)
            guard !raw.isEmpty else { continue }
            parts.append((analyzer.analyze(samples: raw, sampleRate: rate, fileDuration: span.length), span.length))
            let signal = SamplePreprocessor.prepare(raw, sampleRate: rate, trimSilence: true)
            let vector = try embedder.embed(extractor.extract(signal: signal))
            segments.append(SegmentEmbedding(start: span.start, end: span.end, embedding: vector))
        }
        guard !segments.isEmpty else { throw AudioDecodeError.empty }

        return .success(id: job.id, duration: info.duration, sampleRate: info.sampleRate, channels: info.channels,
                        embedding: FieldRecording.composite(segments), fingerprint: FileFingerprint.compute(url: job.url),
                        modelVersion: embedder.version, cues: CueFileReader.read(url: job.url),
                        descriptors: FieldRecording.aggregate(parts), segments: segments)
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
