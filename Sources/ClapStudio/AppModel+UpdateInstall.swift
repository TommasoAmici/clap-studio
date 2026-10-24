import AppKit
import ClapCore

extension AppModel {
    func installUpdate(_ update: ReleaseUpdate) {
        guard updateInstallTask == nil else { return }
        isInstallingUpdate = true
        statusMessage = "Downloading Clap Studio \(update.version.version)…"
        updateInstallTask = Task { [weak self] in
            guard let self else { return }
            do {
                let destination = try await Task.detached(priority: .userInitiated) { [self] in
                    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("clap-update-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
                    defer { try? FileManager.default.removeItem(at: scratch) }
                    let archive = try await ReleaseDownloader.download(update, into: scratch)
                    await MainActor.run { self.statusMessage = "Verifying and installing the update…" }
                    return try ReleaseInstaller.install(archive: archive, version: update.version,
                                                        applications: ReleaseInstaller.applicationsDirectory())
                }.value
                self.statusMessage = "Clap Studio \(update.version.version) is installed. Restart to use it."
                await self.offerUpdateRestart(at: destination)
            } catch {
                self.statusMessage = ""
                self.errorMessage = "Could not update Clap Studio. \(error.localizedDescription) Your samples and library are unchanged."
            }
            self.isInstallingUpdate = false
            self.updateInstallTask = nil
        }
    }

    func offerUpdateRestart(at app: URL) async {
        guard let window = await waitForUpdateWindow() else { return }
        showUpdateRestart(at: app, on: window)
    }

    func showUpdateRestart(at app: URL, on window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Clap Studio is ready to restart"
        alert.informativeText = "The update is installed at \(app.path). Restart to use it. Your samples and library are kept."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        updateAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.updateAlert = nil
            if response == .alertFirstButtonReturn { self?.restartAfterUpdate(app) }
        }
    }

    private func restartAfterUpdate(_ app: URL) {
        // Launch only after normal termination has flushed the app's library writes.
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "attempt=0; while [ \"$attempt\" -lt 120 ]; do if ! kill -0 \"$1\" 2>/dev/null; then /usr/bin/open \"$2\"; exit; fi; /bin/sleep 1; attempt=$((attempt + 1)); done",
                            "clap-update", String(ProcessInfo.processInfo.processIdentifier), app.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            errorMessage = "The update is installed at \(app.path), but Clap Studio could not restart. Quit and open it from Applications. Your samples and library are kept."
        }
    }
}
