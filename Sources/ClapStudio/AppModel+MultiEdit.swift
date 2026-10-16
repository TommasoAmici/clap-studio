import ClapCore
import Foundation

/// Editing several samples at once from the inspector.
extension AppModel {
    /// The samples highlighted in the list, in list order. Empty unless more than one is highlighted in the library.
    var multiSelection: [SampleRecord] {
        guard viewMode == .library, tableSelection.count > 1 else { return [] }
        return visible.filter { tableSelection.contains($0.id) }
    }

    /// Sets (or with nil clears) the tempo of several loops at once, as one undoable change.
    func setBPM(_ ids: [Int64], _ bpm: Double?) {
        let before = ids.compactMap { id in sampleByID[id].map { (id: id, bpm: $0.bpmManual) } }
        let changed = before.filter { $0.bpm != bpm }
        guard !changed.isEmpty else { return }
        let after = changed.map { (id: $0.id, bpm: bpm) }
        let name = bpm.map { "Set Tempo to \(Format.bpm($0)) for \(samplesPhrase(changed.count))" }
            ?? "Use Detected Tempo for \(samplesPhrase(changed.count))"
        record(LibraryEdit(name: name,
                           undo: { [unowned self] in applyBPMs(changed) },
                           redo: { [unowned self] in applyBPMs(after) }))
        applyBPMs(after)
    }

    private func applyBPMs(_ values: [(id: Int64, bpm: Double?)]) {
        guard let store, !values.isEmpty else { return }
        do { try store.setManualBPMs(values) } catch { errorMessage = "Could not save the tempo: \(error)"; return }
        for value in values { mutate(value.id) { $0.bpmManual = value.bpm } }
        if descriptorFilter.isActive { refilter() }
    }
}

extension Format {
    /// "128" or "127.5".
    static func bpm(_ value: Double) -> String { String(format: value.rounded() == value ? "%.0f" : "%.1f", value) }
}
