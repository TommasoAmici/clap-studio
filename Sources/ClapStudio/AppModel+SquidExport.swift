import ClapCore
import Foundation

/// What the export sheet asks for.
enum SquidPlan {
    case bank(set: String?, number: Int, name: String, replace: Bool)
    case addToBank(set: String?, number: Int)
    case pool(subfolder: String)
}

/// Where samples were last sent, so the sheet starts there the next time.
struct SquidLastDestination: Codable, Equatable {
    var drive: String
    var pool: Bool
    var set: String?
    var bank: Int?
    var poolFolder: String

    private static let key = "squid.lastDestination"

    static func load() -> SquidLastDestination? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SquidLastDestination.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Sending samples to a stick.
extension AppModel {
    /// Opens the export sheet. `ids` fill the bank (or the Pool). The drive and place come from where the user is
    /// looking; failing that, from where samples were last sent.
    func openSquidExport(ids: [Int64], drive: String? = nil, set: String? = nil, pool: Bool = false, bank: Int? = nil) {
        guard squidEnabled else { return }
        squidItems = ids
        var target = SquidTarget(drive: drive ?? usbSelection?.drive ?? usbDrives.first?.id, set: set, pool: pool, bank: bank)
        if drive == nil, let selection = usbSelection {
            switch selection.area {
            case .pool: target.pool = true
            case .set(let name): target.set = name
            }
        }
        let chosenByContext = drive != nil || set != nil || pool || bank != nil || usbSelection != nil
        if !chosenByContext, let last = SquidLastDestination.load(), let contents = usbContents[last.drive],
           usbDrives.contains(where: { $0.id == last.drive }) {
            // A set that has since been renamed or removed is not offered; the bank goes with it.
            let setStillThere = last.set == nil || contents.set(named: last.set) != nil
            target = SquidTarget(drive: last.drive, set: setStillThere ? last.set : nil, pool: last.pool,
                                 bank: setStillThere ? last.bank : nil, poolFolder: last.poolFolder)
        }
        squidTarget = target
        showSquidExport = true
    }

    /// Remembers where samples went, for the next time the sheet opens.
    func rememberSquidDestination(_ plan: SquidPlan, driveID: String) {
        switch plan {
        case .bank(let set, let number, _, _), .addToBank(let set, let number):
            SquidLastDestination(drive: driveID, pool: false, set: set, bank: number, poolFolder: "").save()
        case .pool(let subfolder):
            SquidLastDestination(drive: driveID, pool: true, set: nil, bank: nil, poolFolder: subfolder).save()
        }
    }

    /// Samples for a sheet that was opened from the library or the drum machine.
    func squidSources() -> [SquidSource] {
        squidItems.compactMap { sampleByID[$0] }.map { SquidSource(file: $0.url, trim: activeTrim(for: $0), name: $0.name, category: $0.effectiveCategory) }
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
                case .addToBank(let set, let number):
                    try SquidExporter.add(sources, set: set, number: number, toVolume: volume)
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
