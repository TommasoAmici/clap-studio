import ClapCore
import Foundation

extension AppModel {
    /// Looks for copies of samples; results appear in the Duplicates sheet.
    func findDuplicates() {
        guard let store, !duplicateSearchRunning else { return }
        duplicateSearchRunning = true
        duplicateGroups = nil
        let samples = samples
        Task {
            let groups = await Task.detached {
                DuplicateFinder.find(store: store, samples: samples)
            }.value
            duplicateGroups = groups
            duplicateSearchRunning = false
        }
    }

    /// Takes samples out of the list and the map without touching the files. Reversible from "Hidden".
    func hide(_ ids: [Int64]) {
        let changed = ids.filter { sampleByID[$0]?.hidden == false }
        guard !changed.isEmpty else { return }
        record(LibraryEdit(name: "Hide \(samplesPhrase(changed.count))",
                           undo: { [unowned self] in setHidden(changed, false) },
                           redo: { [unowned self] in setHidden(changed, true) }))
        setHidden(changed, true)
        if let selectedID, ids.contains(selectedID) { select(nil) }
        // Groups that are no longer duplicates drop out of the sheet.
        let gone = Set(ids)
        duplicateGroups = duplicateGroups?.compactMap { group in
            let rest = group.ids.filter { !gone.contains($0) }
            return rest.count > 1 ? DuplicateGroup(id: group.id, ids: rest) : nil
        }
    }

    func unhide(_ ids: [Int64]) {
        let changed = ids.filter { sampleByID[$0]?.hidden == true }
        guard !changed.isEmpty else { return }
        record(LibraryEdit(name: "Show \(samplesPhrase(changed.count))",
                           undo: { [unowned self] in setHidden(changed, true) },
                           redo: { [unowned self] in setHidden(changed, false) }))
        setHidden(changed, false)
    }

    private func setHidden(_ ids: [Int64], _ hidden: Bool) {
        guard let store, !ids.isEmpty else { return }
        do { try store.setHidden(ids, hidden) } catch { errorMessage = "Could not update the library: \(error)"; return }
        for id in ids { mutate(id) { $0.hidden = hidden } }
        updateHiddenCount()
        if smartFilter == .hidden, hiddenCount == 0 { smartFilter = .all } else { refilter() }
    }

    /// Used by the insights sheet; empty until the map index exists.
    func reuseSuggestions() -> [ReuseSuggestion] {
        guard let index = snapshot?.index else { return [] }
        return ReuseInsights.suggestions(samples: samples, index: index)
    }

    func updateHiddenCount() { hiddenCount = samples.lazy.filter(\.hidden).count }
}
