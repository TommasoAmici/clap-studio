import Foundation

/// Keeps WAV files in step with the app's cue points, so users never have to save cues by hand.
///
/// Edits are written shortly after the last change (debounced), on a background queue, using the
/// verified atomic `WavCueWriter`. Other formats cannot store cues and stay app-only.
public final class CueFileSync: @unchecked Sendable {
    public enum Outcome: Sendable, Equatable {
        case written(sampleID: Int64)
        case appOnly(sampleID: Int64)                    // format cannot hold cues
        case failed(sampleID: Int64, message: String)
    }

    private let store: LibraryStore
    private let delay: TimeInterval
    private let onOutcome: @Sendable (Outcome) -> Void
    private let queue = DispatchQueue(label: "clapstudio.cue-file-sync", qos: .utility)
    private let lock = NSLock()
    private var pending: [Int64: DispatchWorkItem] = [:]

    public init(store: LibraryStore, delay: TimeInterval = 0.8, onOutcome: @escaping @Sendable (Outcome) -> Void = { _ in }) {
        self.store = store
        self.delay = delay
        self.onOutcome = onOutcome
    }

    /// Schedules a write; further edits within `delay` are coalesced into one.
    public func markChanged(sampleID: Int64) {
        let item = DispatchWorkItem { [weak self] in self?.writeNow(sampleID) }
        lock.lock()
        pending[sampleID]?.cancel()
        pending[sampleID] = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Writes everything that is pending right now and waits for it (used when the app quits).
    public func flush() {
        lock.lock()
        let ids = Array(pending.keys)
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        lock.unlock()
        queue.sync { for id in ids { writeNow(id) } }
    }

    /// Writes cues left unsaved by an earlier session. Runs in the background.
    public func syncAllDirty() {
        for id in store.dirtyCueSampleIDs() { markChanged(sampleID: id) }
    }

    private func writeNow(_ id: Int64) {
        lock.lock(); pending[id] = nil; lock.unlock()
        guard store.cuesDirty(sampleID: id), let sample = store.sample(id: id) else { return }
        guard Self.canStoreCues(ext: sample.ext) else { onOutcome(.appOnly(sampleID: id)); return }
        do {
            try store.writeCuesToFile(sample: sample, keepBackup: false)
            onOutcome(.written(sampleID: id))
        } catch {
            onOutcome(.failed(sampleID: id, message: String(describing: error)))
        }
    }

    public static func canStoreCues(ext: String) -> Bool {
        let e = ext.lowercased()
        return e == "wav" || e == "wave"
    }
}
