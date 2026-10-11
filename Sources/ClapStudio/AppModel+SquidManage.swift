import ClapCore
import Foundation

/// Managing a stick from the app, the way Finder manages folders: new, rename, duplicate, move, move to Trash.
/// Each change is made on the stick, then the app looks at the stick again, so what is shown is what is on the disk.
extension AppModel {
    /// Runs a change on a stick off the main thread. Shows the problem and returns nil if it fails.
    @discardableResult
    private func changeUsb<T: Sendable>(_ driveID: String, _ work: @escaping @Sendable (URL) throws -> T) async -> T? {
        guard let volume = drive(id: driveID)?.url else { return nil }
        let outcome: Result<T, Error> = await Task.detached { Result { try work(volume) } }.value
        await reloadUsb()
        switch outcome {
        case .success(let value): return value
        case .failure(let error): errorMessage = error.localizedDescription; return nil
        }
    }

    private func uniqueName(_ base: String, among taken: [String]) -> String {
        var name = base, n = 2
        while taken.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    // MARK: sets

    /// Makes a set with a placeholder name and puts its name in edit mode, like a new folder in Finder.
    func newSet(on driveID: String) {
        let taken = usbContents[driveID]?.sets.compactMap(\.name) ?? []
        let name = uniqueName("New", among: taken)
        Task {
            guard await changeUsb(driveID, { try SquidManager.createSet(name: name, volume: $0) }) != nil else { return }
            selectSidebar(UsbSelection(drive: driveID, area: .set(name)).tag)
            renamingUsb = .set(drive: driveID, name: name)
        }
    }

    func renameSet(drive driveID: String, from old: String, to new: String) {
        renamingUsb = nil
        Task {
            guard await changeUsb(driveID, { try SquidManager.renameSet(old, to: new, volume: $0) }) != nil else { return }
            guard let selection = usbSelection, selection.drive == driveID else { return }
            switch selection.area {
            case .set(old): selectSidebar(UsbSelection(drive: driveID, area: .set(new)).tag)
            case .bank(old, let number): selectSidebar(UsbSelection(drive: driveID, area: .bank(set: new, number: number)).tag)
            default: break
            }
        }
    }

    func trashSet(drive driveID: String, name: String) {
        Task { await changeUsb(driveID) { try SquidManager.trashSet(name, volume: $0) } }
    }

    // MARK: banks

    func newBank(drive driveID: String, set: String?) {
        Task {
            guard let number = await changeUsb(driveID, { try SquidManager.createBank(set: set, volume: $0) }) else { return }
            // The name is edited on the bank's card, so show a view that has it: the set's, or the new bank's own.
            if usbSelection != UsbSelection(drive: driveID, area: .set(set)) {
                selectSidebar(UsbSelection(drive: driveID, area: .bank(set: set, number: number)).tag)
            }
            renamingUsb = .bank(drive: driveID, set: set, number: number)
        }
    }

    func renameBank(drive driveID: String, set: String?, number: Int, to name: String) {
        renamingUsb = nil
        Task { await changeUsb(driveID) { try SquidManager.renameBank(set: set, number: number, to: name, volume: $0) } }
    }

    func duplicateBank(drive driveID: String, set: String?, number: Int) {
        Task { await changeUsb(driveID) { try SquidManager.duplicateBank(set: set, number: number, volume: $0) } }
    }

    func moveBank(drive driveID: String, set: String?, number: Int, to target: String?) {
        Task { await changeUsb(driveID) { try SquidManager.moveBank(set: set, number: number, toSet: target, volume: $0) } }
    }

    func trashBank(drive driveID: String, set: String?, number: Int) {
        Task { await changeUsb(driveID) { try SquidManager.trashBank(set: set, number: number, volume: $0) } }
    }

    func trashUsbSample(drive driveID: String, set: String?, number: Int, slot: Int) {
        Task { await changeUsb(driveID) { try SquidManager.trashSample(set: set, number: number, slot: slot, volume: $0) } }
    }
}
