import ClapCore
import Foundation

extension AppModel {
    func updateTagCounts() {
        var counts: [String: (name: String, count: Int)] = [:]
        for s in samples {
            for tag in s.tags {
                let key = tag.lowercased()
                counts[key] = (counts[key]?.name ?? tag, (counts[key]?.count ?? 0) + 1)
            }
        }
        tagCounts = counts.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let tag = tagFilter, !tagCounts.contains(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame }) { tagFilter = nil }
    }

    func addTag(_ raw: String, to ids: [Int64]) {
        let tag = LibraryStore.cleanTag(raw)
        let changed = ids.filter { id in sampleByID[id].map { s in !s.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } } ?? false }
        guard !tag.isEmpty, !changed.isEmpty else { return }
        record(LibraryEdit(name: "Tag \(samplesPhrase(changed.count)) \"\(tag)\"",
                           undo: { [unowned self] in applyTag(tag, to: changed, add: false) },
                           redo: { [unowned self] in applyTag(tag, to: changed, add: true) }))
        applyTag(tag, to: changed, add: true)
    }

    func removeTag(_ tag: String, from ids: [Int64]) {
        let changed = ids.filter { sampleByID[$0]?.tags.contains(tag) == true }
        guard !changed.isEmpty else { return }
        record(LibraryEdit(name: "Remove tag \"\(tag)\"",
                           undo: { [unowned self] in applyTag(tag, to: changed, add: true) },
                           redo: { [unowned self] in applyTag(tag, to: changed, add: false) }))
        applyTag(tag, to: changed, add: false)
    }

    func applyTag(_ tag: String, to ids: [Int64], add: Bool) {
        guard let store else { return }
        do {
            if add { try store.addTag(tag, to: ids) } else { try store.removeTag(tag, from: ids) }
        } catch { errorMessage = "Could not save the tag: \(error)"; return }
        for id in ids {
            mutate(id) { s in
                if add { s.tags = (s.tags + [tag]).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
                else { s.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame } }
            }
        }
        updateTagCounts()
        if tagFilter != nil || !searchText.isEmpty { refilter() }
    }
}
