import AppKit
import ClapCore

extension AppModel {
    var showJoin: Bool {
        get { join.show }
        set { join.show = newValue }
    }
    var joinSources: [JoinSource] {
        get { join.sources }
        set { join.sources = newValue }
    }
    var isJoining: Bool {
        get { join.running }
        set { join.running = newValue }
    }
    var joinTask: Task<Void, Never>? {
        get { join.task }
        set { join.task = newValue }
    }
    var pendingJoinSettings: JoinSettings? {
        get { join.pendingSettings }
        set { join.pendingSettings = newValue }
    }
    var joinFolderPanel: NSOpenPanel? {
        get { join.folderPanel }
        set { join.folderPanel = newValue }
    }

    var joinActionTargets: [Int64] {
        viewMode == .map && !mapSelection.isEmpty ? mapSelection : actionTargets
    }

    func openJoin(ids: [Int64]) {
        guard !isJoining else { return }
        let selected = Set(ids)
        var ordered = visible.filter { selected.contains($0.id) }
        let included = Set(ordered.map(\.id))
        ordered += ids.compactMap { included.contains($0) ? nil : sampleByID[$0] }
        guard ordered.count > 1 else { return }
        joinSources = ordered.map { JoinSource(url: $0.url, trim: activeTrim(for: $0), name: $0.name, sampleID: $0.id) }
        showJoin = true
    }

    /// Waits for the options sheet to close before presenting the native folder chooser.
    func queueJoin(settings: JoinSettings) {
        guard settings.isValid, !isJoining else { return }
        pendingJoinSettings = settings
        showJoin = false
    }

    func joinSheetDismissed() {
        guard let settings = pendingJoinSettings else { joinSources = []; return }
        pendingJoinSettings = nil
        let sources = joinSources
        Task { [self] in
            await Task.yield()
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Join Here"
            panel.message = "Save joined WAV files in this folder"
            joinFolderPanel = panel
            let completed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else { return }
                self.joinFolderPanel = nil
                guard response == .OK, let folder = panel.url else {
                    self.showJoin = true
                    return
                }
                self.joinSources = []
                self.startJoining(sources, settings: settings, to: folder)
            }
            if let window = NSApp.mainWindow ?? NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: completed)
            } else {
                panel.begin(completionHandler: completed)
            }
        }
    }

    private func startJoining(_ sources: [JoinSource], settings: JoinSettings, to folder: URL) {
        joinTask?.cancel()
        isJoining = true
        joinTask = Task {
            defer { isJoining = false; joinTask = nil }
            let store = self.store
            let worker = Task.detached(priority: .userInitiated) { () throws -> ([JoinedOutput], [Int64: Set<String>]?) in
                let outputs = try JoinExporter.exportWithRegions(sources, settings: settings, to: folder)
                do {
                    guard let store else { return (outputs, nil) }
                    try store.recordJoinedOutputs(outputs, sources: sources)
                    return (outputs, store.joinedRelativePathsByRoot())
                } catch { return (outputs, nil) }
            }
            do {
                let (outputs, joinedPaths) = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                                                 onCancel: { worker.cancel() })
                let files = outputs.map(\.url)
                if let joinedPaths {
                    joinedLinksRevision &+= 1
                    let changed = JoinedLibrary.markJoined(in: &samples, pathsByRoot: joinedPaths)
                    for id in changed { sampleByID[id]?.isJoined = true }
                    if !changed.isEmpty { refilter() }
                    statusMessage = "Saved \(files.count) joined \(files.count == 1 ? "file" : "files")."
                } else {
                    errorMessage = "Joined files were saved, but their source links could not be saved. Source files were not changed."
                }
                NSWorkspace.shared.activateFileViewerSelecting(files)
            } catch is CancellationError {
                statusMessage = "Joining cancelled. Source files were not changed."
            } catch {
                errorMessage = "Could not join the samples: \(error.localizedDescription) Source files were only read, never changed."
            }
        }
    }

    func cancelJoin() { joinTask?.cancel() }
}
