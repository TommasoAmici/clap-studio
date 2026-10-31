import ClapCore
import Foundation

/// What the export sheet asks for.
enum SquidPlan {
    /// `slots` has one entry per sheet row (nil: not sent). `replace` writes the first bank afresh after moving the old one to the Trash.
    /// `overwrite` lets a channel that already holds a sample be replaced (following banks; the sheet warned about it).
    case banks(set: String?, firstBank: Int, bankName: String, slots: [SquidSlot?], replace: Bool, overwrite: Bool)
    case pool(subfolder: String)
    /// The samples are joined first (ALM Squid Salmple limits), then sent to `channel` of `firstBank` and the banks after it.
    case joined(set: String?, firstBank: Int, channel: Int, bankName: String, name: String)
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
    func openSquidExport(ids: [Int64], drive: String? = nil, set: String? = nil, pool: Bool = false, bank: Int? = nil,
                         poolFolder: String = "") {
        guard squidEnabled else { return }
        squidItems = ids
        squidChannels = [:]
        var target = SquidTarget(drive: drive ?? usbSelection?.drive ?? usbDrives.first?.id, set: set, pool: pool, bank: bank,
                                 poolFolder: poolFolder)
        if drive == nil, let selection = usbSelection {
            switch selection.area {
            case .pool: target.pool = true
            case .poolFolder(let path): target.pool = true; target.poolFolder = path.joined(separator: "/")
            case .set(let name): target.set = name
            case .bank(let set, let number): target.set = set; target.bank = number
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
        case .banks(let set, let firstBank, _, _, _, _):
            SquidLastDestination(drive: driveID, pool: false, set: set, bank: firstBank, poolFolder: "").save()
        case .joined(let set, let firstBank, _, _, _):
            SquidLastDestination(drive: driveID, pool: false, set: set, bank: firstBank, poolFolder: "").save()
        case .pool(let subfolder):
            SquidLastDestination(drive: driveID, pool: true, set: nil, bank: nil, poolFolder: subfolder).save()
        }
    }

    /// The sample for a row of the sheet, ready to convert; nil when it has left the library.
    func squidSource(for id: Int64) -> SquidSource? {
        guard let sample = sampleByID[id] else { return nil }
        return SquidSource(file: sample.url, trim: activeTrim(for: sample), name: sample.name,
                           category: sample.effectiveCategory, matchLevel: squidMatchLevels)
    }

    /// Samples for a sheet that was opened from the library or the drum machine.
    func squidSources() -> [SquidSource] { squidItems.compactMap { squidSource(for: $0) } }

    /// Writes the plan to the drive, then refreshes what the app shows of it. Returns an error message, or nil on success.
    func sendToSquid(_ plan: SquidPlan, driveID: String) async -> String? {
        if case .joined(let set, let firstBank, let channel, let bankName, let name) = plan {
            return await sendJoinedToSquid(set: set, firstBank: firstBank, channel: channel, bankName: bankName, name: name, driveID: driveID)
        }
        guard let drive = drive(id: driveID) else { return "The drive is no longer connected." }
        let rows = squidItems.map { squidSource(for: $0) }
        guard rows.contains(where: { $0 != nil }) else { return "Add at least one sample." }
        let volume = drive.url
        let outcome: Result<Void, Error> = await Task.detached {
            do {
                switch plan {
                case .banks(let set, let firstBank, let bankName, let slots, let replace, let overwrite):
                    let placed = zip(rows, slots).compactMap { row, slot in
                        row.flatMap { source in slot.map { SquidPlacedSource(source: source, slot: $0) } }
                    }
                    if replace {
                        var channels = [SquidSource?](repeating: nil, count: SquidLayout.slotsPerBank)
                        for item in placed where item.slot.bank == firstBank { channels[item.slot.channel - 1] = item.source }
                        try SquidExporter.export(SquidBankRequest(set: set, number: firstBank, name: bankName, slots: channels,
                                                                  replaceExisting: true), toVolume: volume)
                    } else {
                        let banks = Set(placed.map(\.slot.bank))
                        try SquidExporter.place(placed, set: set, bankNames: Dictionary(uniqueKeysWithValues: banks.map { ($0, bankName) }),
                                                toVolume: volume, overwrite: overwrite)
                    }
                case .pool(let subfolder):
                    try SquidExporter.exportToPool(rows.compactMap { $0 }, subfolder: subfolder, toVolume: volume)
                case .joined: break
                }
                return .success(())
            } catch { return .failure(error) }
        }.value
        return finishSquidWrite(outcome, volume: volume)
    }

    /// After anything was written to a stick: forget cached audio of replaced files and read the stick again.
    func finishSquidWrite(_ outcome: Result<Void, Error>, volume: URL) -> String? {
        player.cache.forget(pathPrefix: SquidStick.rootURL(volume: volume).path)      // files may have been replaced
        refreshUsbDrives(settle: false)
        if case .failure(let error) = outcome { return error.localizedDescription }
        return nil
    }
}
