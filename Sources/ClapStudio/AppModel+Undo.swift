import Foundation

/// An edit to the library's organisation (hiding, favorites, collections) that can be taken back.
struct LibraryEdit {
    let name: String
    let undo: @MainActor () -> Void
    let redo: @MainActor () -> Void
}

extension AppModel {
    func record(_ edit: LibraryEdit) {
        undoStack.append(edit)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }

    var undoName: String? { undoStack.last?.name }
    var redoName: String? { redoStack.last?.name }

    func undoLibraryEdit() {
        guard let edit = undoStack.popLast() else { return }
        edit.undo()
        redoStack.append(edit)
    }

    func redoLibraryEdit() {
        guard let edit = redoStack.popLast() else { return }
        edit.redo()
        undoStack.append(edit)
    }

    /// "1 sample" / "3 samples".
    func samplesPhrase(_ count: Int) -> String { count == 1 ? "1 sample" : "\(count) samples" }
}
