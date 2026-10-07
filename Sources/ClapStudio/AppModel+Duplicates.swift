import ClapCore
import Foundation

extension AppModel {
    /// Looks for copies of samples; results appear in the Duplicates sheet.
    func findDuplicates() {
        guard let store, !duplicateSearchRunning else { return }
        duplicateSearchRunning = true
        duplicateGroups = nil
        let samples = samples
        let version = store.meta("model_version") ?? ""
        Task {
            let groups = await Task.detached {
                (try? DuplicateFinder.find(store: store, samples: samples, modelVersion: version)) ?? []
            }.value
            duplicateGroups = groups
            duplicateSearchRunning = false
        }
    }

    /// Takes samples out of the list and the map without touching the files. Reversible from "Hidden".
    func hide(_ ids: [Int64]) {
        setHidden(ids, true)
        if let selectedID, ids.contains(selectedID) { select(nil) }
        // Groups that are no longer duplicates drop out of the sheet.
        let gone = Set(ids)
        duplicateGroups = duplicateGroups?.compactMap { group in
            let rest = group.ids.filter { !gone.contains($0) }
            return rest.count > 1 ? DuplicateGroup(id: group.id, ids: rest, identical: group.identical) : nil
        }
    }

    func unhide(_ ids: [Int64]) { setHidden(ids, false) }

    private func setHidden(_ ids: [Int64], _ hidden: Bool) {
        guard let store, !ids.isEmpty else { return }
        do { try store.setHidden(ids, hidden) } catch { errorMessage = "Could not update the library: \(error)"; return }
        for id in ids { mutate(id) { $0.hidden = hidden } }
        updateHiddenCount()
        if smartFilter == .hidden, hiddenCount == 0 { smartFilter = .all } else { refilter() }
    }

    func updateHiddenCount() { hiddenCount = samples.lazy.filter(\.hidden).count }
}
