import ClapCore
import Foundation

/// What the export sheet asks for.
enum SquidPlan {
    case bank(set: String?, number: Int, name: String, replace: Bool)
    case pool(subfolder: String)
}

/// Sending samples to a stick.
extension AppModel {
    /// Opens the export sheet. `ids` fill the bank (or the Pool); the drive and place come from where the user is looking.
    func openSquidExport(ids: [Int64], drive: String? = nil, set: String? = nil, pool: Bool = false) {
        guard squidEnabled else { return }
        squidItems = ids
        var target = SquidTarget(drive: drive ?? usbSelection?.drive ?? usbDrives.first?.id, set: set, pool: pool)
        if drive == nil, let selection = usbSelection {
            switch selection.area {
            case .pool: target.pool = true
            case .set(let name): target.set = name
            }
        }
        squidTarget = target
        showSquidExport = true
    }

    /// Samples for a sheet that was opened from the tray or the drum machine.
    func squidSources() -> [SquidSource] {
        squidItems.compactMap { sampleByID[$0] }.map { SquidSource(file: $0.url, trim: activeTrim(for: $0), name: $0.name) }
    }

    /// Writes the plan to the drive, then refreshes what the app shows of it. Returns an error message, or nil on success.
    func sendToSquid(_ plan: SquidPlan, driveID: String) async -> String? {
        guard let drive = drive(id: driveID) else { return "The drive is no longer connected." }
        let sources = squidSources()
        guard !sources.isEmpty else { return "Add at least one sample." }
        let volume = drive.url
        let outcome: Result<Void, Error> = await Task.detached {
            do {
                switch plan {
                case .bank(let set, let number, let name, let replace):
                    try SquidExporter.export(SquidBankRequest(set: set, number: number, name: name,
                                                              slots: sources.prefix(SquidLayout.slotsPerBank).map { Optional($0) },
                                                              replaceExisting: replace), toVolume: volume)
                case .pool(let subfolder):
                    try SquidExporter.exportToPool(sources, subfolder: subfolder, toVolume: volume)
                }
                return .success(())
            } catch { return .failure(error) }
        }.value
        refreshUsbDrives(settle: false)
        if case .failure(let error) = outcome { return error.localizedDescription }
        return nil
    }
}
