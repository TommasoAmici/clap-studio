import AppKit
import ClapCore

extension AppModel {
    /// Release builds check quietly on launch and once a day; development snapshots never contact GitHub.
    func startUpdateChecks() {
        guard updateScheduleTask == nil, installedReleaseVersion != nil else { return }
        #if DEBUG
        guard ProcessInfo.processInfo.environment["CLAP_SNAPSHOT"] == nil else { return }
        #endif
        updateScheduleTask = Task { [weak self] in
            self?.checkForUpdates(manual: false, onLaunch: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
                self?.checkForUpdates(manual: false)
            }
        }
    }

    var installedReleaseVersion: ReleaseVersion? {
        ReleaseVersion(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                       build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    func checkForUpdates(manual: Bool, onLaunch: Bool = false) {
        guard let installed = installedReleaseVersion else {
            if manual { errorMessage = "To check for updates, open the Clap Studio app bundle. This development build has no release version." }
            return
        }
        let defaults = UserDefaults.standard
        guard manual || (!isCheckingUpdates && UpdateSchedule.shouldCheck(now: Date(), lastCheck: defaults.object(forKey: "updates.lastCheck") as? Date, onLaunch: onLaunch)) else { return }
        updateCheckTask?.cancel()
        isCheckingUpdates = true
        defaults.set(Date(), forKey: "updates.lastCheck")
        updateCheckTask = Task { [weak self] in
            do {
                let update = try await ReleaseChecker.latest(installed: installed)
                try Task.checkCancellation()
                guard let self else { return }
                if let update {
                    if manual || defaults.string(forKey: "updates.skippedTag") != update.tag {
                        await self.presentUpdate(update)
                    }
                } else if manual {
                    self.errorMessage = "Clap Studio is up to date."
                }
            } catch {
                guard !Task.isCancelled else { return }
                if manual { self?.errorMessage = "Could not check for updates. \(error.localizedDescription) Your samples and library are unchanged." }
            }
            guard !Task.isCancelled else { return }
            self?.isCheckingUpdates = false
            self?.updateCheckTask = nil
        }
    }

    /// Waits until an existing chooser or sheet is closed so it is never displaced by a background check.
    private func presentUpdate(_ update: ReleaseUpdate) async {
        while !Task.isCancelled {
            if NSApp.isActive, NSApp.modalWindow == nil,
               let window = NSApp.mainWindow ?? NSApp.keyWindow,
               window.sheetParent == nil, !window.isSheet, window.attachedSheet == nil {
                await withCheckedContinuation { continuation in
                    showUpdatePrompt(update, on: window) { continuation.resume() }
                }
                return
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }

    func showUpdatePrompt(_ update: ReleaseUpdate, on window: NSWindow, dismissed: @escaping () -> Void = {}) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "A new Clap Studio update is available"
        alert.informativeText = "Version \(update.version.version) (build \(update.version.build)) is ready. Open its GitHub release page to download the app and read what changed. Your samples and library are kept."
        alert.addButton(withTitle: "Open Release")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Update")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        updateAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(update.pageURL) }
            if response == .alertThirdButtonReturn { UserDefaults.standard.set(update.tag, forKey: "updates.skippedTag") }
            self?.updateAlert = nil
            dismissed()
        }
    }
}
