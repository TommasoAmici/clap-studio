import ClapCore
import Foundation

/// Editing several samples at once from the inspector.
extension AppModel {
    /// The samples highlighted in the list. Empty unless more than one is highlighted in the library.
    var multiSelection: [SampleRecord] {
        guard viewMode == .library, tableSelection.count > 1 else { return [] }
        return tableSelection.compactMap { sampleByID[$0] }.sorted { $0.id < $1.id }
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

    /// The sound edit a sample has (neutral when none).
    func edit(for sample: SampleRecord) -> SampleEdit { activeTrim(for: sample)?.edit ?? SampleEdit() }

    /// Changes one or more parts of the sound edit of several samples at once, as one undoable change. Each keeps
    /// its own trim and the parts of its edit that `change` leaves alone.
    func changeEdits(_ ids: [Int64], _ change: (inout SampleEdit) -> Void) {
        let updates = ids.compactMap { id -> (id: Int64, trim: SampleTrim?)? in
            guard let sample = sampleByID[id], sample.duration > 0 else { return nil }
            let current = activeTrim(for: sample) ?? SampleTrim(start: 0, end: sample.duration)
            var edit = current.edit
            change(&edit)
            return (id, SampleTrim(start: current.start, end: current.end, fadeOut: current.fadeOut, edit: edit.clamped()))
        }
        setTrims(updates, actionName: "Edit Sound for \(samplesPhrase(updates.count))")
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
