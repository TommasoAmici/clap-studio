import Foundation

/// Which species occur at a place. Looking up a place takes a few milliseconds; the answers are remembered.
public final class BirdLocationFilter: @unchecked Sendable {
    private let model: BirdLocationModel
    private let labels: BirdLabels
    private let threshold: Float
    private var cache: [String: Set<String>] = [:]
    private let lock = NSLock()

    public init(model: BirdLocationModel, labels: BirdLabels, threshold: Float = BirdLocationModel.defaultThreshold) {
        self.model = model
        self.labels = labels
        self.threshold = threshold
    }

    /// Scientific names of the species that occur at `point` at some time of the year.
    public func allowed(at point: GeoPoint) throws -> Set<String> {
        let key = String(format: "%.2f,%.2f", point.latitude, point.longitude)
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let probabilities = try model.probabilities(latitude: point.latitude, longitude: point.longitude, week: nil)
        var names: Set<String> = []
        for (i, p) in probabilities.enumerated() where p >= threshold && i < labels.species.count {
            names.insert(labels.species[i].scientific)
        }
        lock.lock(); cache[key] = names; lock.unlock()
        return names
    }
}

/// Listens to every field recording that has not been listened to, and keeps the stored species in step with the
/// places the user gives.
public enum BirdSpeciesIndexer {
    /// Returns how many recordings were listened to. Stops between recordings when cancelled; a recording
    /// interrupted part-way keeps nothing and is listened to again next time.
    @discardableResult
    public static func run(store: LibraryStore, detector: BirdDetector, filter: BirdLocationFilter?,
                           onProgress: @escaping @Sendable (_ done: Int, _ total: Int, _ name: String) -> Void = { _, _, _ in },
                           isCancelled: @escaping @Sendable () -> Bool = { false }) -> Int {
        let jobs = store.recordingsNeedingSpecies()
        var done = 0
        for job in jobs {
            if isCancelled() { break }
            onProgress(done, jobs.count, job.name)
            guard let found = try? detector.detect(url: job.url, duration: job.duration, isCancelled: isCancelled) else {
                if isCancelled() { break }
                continue            // unreadable file: leave it, it is tried again next time
            }
            let allowed = allowedSet(for: store.effectiveLocation(sampleID: job.id), filter: filter)
            do { try store.saveSpecies(sampleID: job.id, detections: found, allowed: allowed) } catch { continue }
            done += 1
        }
        onProgress(done, jobs.count, "")
        return done
    }

    /// Applies the current places to everything already listened to (after the user sets a place).
    public static func refilter(store: LibraryStore, filter: BirdLocationFilter?, sampleIDs: [Int64]? = nil) {
        for id in sampleIDs ?? store.recordingsWithSpecies() {
            try? store.refilterSpecies(sampleID: id, allowed: allowedSet(for: store.effectiveLocation(sampleID: id), filter: filter))
        }
    }

    private static func allowedSet(for place: GeoPoint?, filter: BirdLocationFilter?) -> Set<String>? {
        guard let place, let filter else { return nil }
        return try? filter.allowed(at: place)
    }
}
