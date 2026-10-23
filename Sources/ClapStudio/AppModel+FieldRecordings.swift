import ClapCore
import Foundation

extension AppModel {
    func treatAsRegularSamples(_ ids: [Int64]) {
        let before = ids.compactMap { sampleByID[$0] }.filter(\.isFieldRecording).map {
            (id: $0.id, regular: $0.isRegularSample, category: $0.categoryManual)
        }
        guard !before.isEmpty else { return }
        let after = before.map {
            (id: $0.id, regular: true, category: $0.category == FieldRecording.categoryName ? nil : $0.category)
        }
        guard applyRegularSamples(after) else { return }
        record(LibraryEdit(name: "Treat as Regular Sample",
                           undo: { [unowned self] in _ = applyRegularSamples(before) },
                           redo: { [unowned self] in _ = applyRegularSamples(after) }))
    }

    @discardableResult
    private func applyRegularSamples(_ values: [(id: Int64, regular: Bool, category: String?)]) -> Bool {
        guard let store else { return false }
        do { try store.setRegularSamples(values) }
        catch {
            errorMessage = "Could not change how these samples are processed: \(error). Files are only read, never moved or changed."
            return false
        }
        segmentCache.invalidate()
        birdsRevision += 1
        reloadSamples()
        if isIndexing { usbIndexQueued = true } else { startIndexing() }
        return true
    }
}
