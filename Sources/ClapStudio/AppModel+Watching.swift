import ClapCore
import Foundation

extension AppModel {
    /// Watches the library folders so new, changed and removed samples are picked up without a manual rescan.
    func restartWatcher() {
        folderWatcher?.stop()
        folderWatcher = nil
        guard !roots.isEmpty else { return }
        let watcher = FolderWatcher(paths: roots.map(\.path)) { [weak self] in
            Task { @MainActor in self?.folderChanged() }
        }
        watcher.start()
        folderWatcher = watcher
    }

    /// Waits for the burst of changes to settle (and for any running index to finish), then rescans once.
    private func folderChanged() {
        rescanTask?.cancel()
        rescanTask = Task {
            try? await Task.sleep(for: .seconds(3))
            while isIndexing, !Task.isCancelled { try? await Task.sleep(for: .seconds(5)) }
            guard !Task.isCancelled else { return }
            startIndexing()
        }
    }
}
