import Foundation

/// Cue editing with undo/redo, backed by the persistent store.
public final class CueEditor: @unchecked Sendable {
    private enum Action {
        case add(CuePoint)
        case remove(CuePoint)
        case move(id: Int64, from: Int64, to: Int64)
        case rename(id: Int64, from: String, to: String)
    }

    private let store: LibraryStore
    private var undoStack: [Action] = []
    private var redoStack: [Action] = []
    private let lock = NSLock()

    public init(store: LibraryStore) { self.store = store }

    public var canUndo: Bool { lock.lock(); defer { lock.unlock() }; return !undoStack.isEmpty }
    public var canRedo: Bool { lock.lock(); defer { lock.unlock() }; return !redoStack.isEmpty }

    @discardableResult
    public func add(sampleID: Int64, frame: Int64, label: String = "") throws -> CuePoint {
        let cue = try store.insertCue(sampleID: sampleID, frame: max(0, frame), label: label)
        record(.add(cue))
        return cue
    }

    public func move(id: Int64, to frame: Int64) throws {
        guard let cue = store.cue(id: id), cue.positionFrames != frame else { return }
        try store.updateCue(id: id, frame: max(0, frame))
        record(.move(id: id, from: cue.positionFrames, to: max(0, frame)))
    }

    public func rename(id: Int64, to label: String) throws {
        guard let cue = store.cue(id: id), cue.label != label else { return }
        try store.updateCue(id: id, label: label)
        record(.rename(id: id, from: cue.label, to: label))
    }

    public func remove(id: Int64) throws {
        guard let cue = store.cue(id: id) else { return }
        try store.deleteCue(id: id)
        record(.remove(cue))
    }

    /// Returns the affected sample id so the UI can refresh.
    @discardableResult
    public func undo() throws -> Int64? {
        lock.lock(); let action = undoStack.popLast(); lock.unlock()
        guard let action else { return nil }
        let sample = try apply(inverse: action)
        lock.lock(); redoStack.append(action); lock.unlock()
        return sample
    }

    @discardableResult
    public func redo() throws -> Int64? {
        lock.lock(); let action = redoStack.popLast(); lock.unlock()
        guard let action else { return nil }
        let sample = try apply(forward: action)
        lock.lock(); undoStack.append(action); lock.unlock()
        return sample
    }

    private func record(_ action: Action) {
        lock.lock(); defer { lock.unlock() }
        undoStack.append(action)
        redoStack.removeAll()
    }

    private func apply(inverse action: Action) throws -> Int64? {
        switch action {
        case .add(let cue): try store.deleteCue(id: cue.id); return cue.sampleID
        case .remove(let cue): try restore(cue); return cue.sampleID
        case .move(let id, let from, _): try store.updateCue(id: id, frame: from); return store.cue(id: id)?.sampleID
        case .rename(let id, let from, _): try store.updateCue(id: id, label: from); return store.cue(id: id)?.sampleID
        }
    }

    private func apply(forward action: Action) throws -> Int64? {
        switch action {
        case .add(let cue): try restore(cue); return cue.sampleID
        case .remove(let cue): try store.deleteCue(id: cue.id); return cue.sampleID
        case .move(let id, _, let to): try store.updateCue(id: id, frame: to); return store.cue(id: id)?.sampleID
        case .rename(let id, _, let to): try store.updateCue(id: id, label: to); return store.cue(id: id)?.sampleID
        }
    }

    private func restore(_ cue: CuePoint) throws {
        try store.insertCue(sampleID: cue.sampleID, frame: cue.positionFrames, label: cue.label,
                            source: cue.source == .file ? .file : .user, fileSynced: false, id: cue.id)
        try store.updateCue(id: cue.id, frame: cue.positionFrames, label: cue.label)
    }
}
