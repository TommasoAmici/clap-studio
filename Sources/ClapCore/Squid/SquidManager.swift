import Foundation

/// Managing what is on a stick the way Finder would: new, rename, duplicate, move, move to Trash. Names are written exactly
/// as given (see `SquidLayout.check`); only a name a folder cannot have is refused.
public enum SquidManager {
    public typealias Trash = (URL) throws -> Void
    public static let moveToTrash: Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    // MARK: sets

    public static func createSet(name: String, volume: URL, fileManager fm: FileManager = .default) throws {
        let contents = SquidStick.read(volume: volume, fileManager: fm)
        let report = SquidLayout.check(setName: name, existing: contents.sets.compactMap(\.name))
        if let problem = report.blockers.first { throw SquidExportError.invalid(problem) }
        if contents.namedSetCount >= SquidLayout.maxSets { throw SquidExportError.tooManySets }
        let folder = SquidStick.rootURL(volume: volume).appendingPathComponent(SquidLayout.setPrefix + name, isDirectory: true)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { throw SquidExportError.failed(error.localizedDescription) }
    }

    public static func renameSet(_ old: String, to new: String, volume: URL, fileManager fm: FileManager = .default) throws {
        let existing = SquidStick.read(volume: volume, fileManager: fm).sets.compactMap(\.name)
        if let problem = SquidLayout.check(setName: new, existing: existing, renaming: old).blockers.first {
            throw SquidExportError.invalid(problem)
        }
        guard let source = SquidStick.setURL(named: old, volume: volume, fileManager: fm) else { throw SquidExportError.missing("Set \(old)") }
        let destination = source.deletingLastPathComponent().appendingPathComponent(SquidLayout.setPrefix + new, isDirectory: true)
        guard source.lastPathComponent != destination.lastPathComponent else { return }
        try move(source, to: destination, fileManager: fm)
    }

    public static func trashSet(_ name: String, volume: URL, trash: Trash = moveToTrash, fileManager fm: FileManager = .default) throws {
        guard let url = SquidStick.setURL(named: name, volume: volume, fileManager: fm) else { throw SquidExportError.missing("Set \(name)") }
        do { try trash(url) } catch { throw SquidExportError.failed("Could not move Set \(name) to the Trash: \(error.localizedDescription)") }
    }

    // MARK: banks

    /// Makes an empty bank at the lowest free number (or the one asked for). Returns its number.
    @discardableResult
    public static func createBank(set: String?, number: Int? = nil, name: String = "", volume: URL,
                                  fileManager fm: FileManager = .default) throws -> Int {
        let contents = SquidStick.read(volume: volume, fileManager: fm)
        guard let free = number ?? contents.freeBankNumbers(inSet: set).first else {
            throw SquidExportError.invalid("A set holds at most \(SquidLayout.maxBanksPerSet) banks.")
        }
        guard SquidStick.bankURL(set: set, number: free, volume: volume, fileManager: fm) == nil else {
            throw SquidExportError.exists(SquidLayout.bankFolder(number: free))
        }
        let container = try containerURL(set: set, volume: volume, create: true, fileManager: fm)
        let bank = container.appendingPathComponent(SquidLayout.bankFolder(number: free), isDirectory: true)
        do {
            try fm.createDirectory(at: bank, withIntermediateDirectories: true)
            if !name.isEmpty { try writeName(name, to: bank) }
        } catch { throw SquidExportError.failed(error.localizedDescription) }
        return free
    }

    /// Changes the name the module shows for a bank (its info.txt). The name is written as typed.
    public static func renameBank(set: String?, number: Int, to name: String, volume: URL, fileManager fm: FileManager = .default) throws {
        guard let bank = SquidStick.bankURL(set: set, number: number, volume: volume, fileManager: fm) else {
            throw SquidExportError.missing(SquidLayout.bankFolder(number: number))
        }
        do { try writeName(name, to: bank) } catch { throw SquidExportError.failed(error.localizedDescription) }
    }

    /// Copies a bank to the lowest free number of the same set. Returns the new number.
    @discardableResult
    public static func duplicateBank(set: String?, number: Int, volume: URL, fileManager fm: FileManager = .default) throws -> Int {
        guard let source = SquidStick.bankURL(set: set, number: number, volume: volume, fileManager: fm) else {
            throw SquidExportError.missing(SquidLayout.bankFolder(number: number))
        }
        guard let free = SquidStick.read(volume: volume, fileManager: fm).freeBankNumbers(inSet: set).first else {
            throw SquidExportError.invalid("A set holds at most \(SquidLayout.maxBanksPerSet) banks.")
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(SquidLayout.bankFolder(number: free), isDirectory: true)
        do { try fm.copyItem(at: source, to: destination) } catch { throw SquidExportError.failed(error.localizedDescription) }
        return free
    }

    /// Moves a bank to the lowest free number of another set. Returns the new number.
    @discardableResult
    public static func moveBank(set: String?, number: Int, toSet target: String?, volume: URL, fileManager fm: FileManager = .default) throws -> Int {
        guard let source = SquidStick.bankURL(set: set, number: number, volume: volume, fileManager: fm) else {
            throw SquidExportError.missing(SquidLayout.bankFolder(number: number))
        }
        guard let free = SquidStick.read(volume: volume, fileManager: fm).freeBankNumbers(inSet: target).first else {
            throw SquidExportError.invalid("A set holds at most \(SquidLayout.maxBanksPerSet) banks.")
        }
        let container = try containerURL(set: target, volume: volume, create: false, fileManager: fm)
        try move(source, to: container.appendingPathComponent(SquidLayout.bankFolder(number: free), isDirectory: true), fileManager: fm)
        return free
    }

    public static func trashBank(set: String?, number: Int, volume: URL, trash: Trash = moveToTrash, fileManager fm: FileManager = .default) throws {
        guard let url = SquidStick.bankURL(set: set, number: number, volume: volume, fileManager: fm) else {
            throw SquidExportError.missing(SquidLayout.bankFolder(number: number))
        }
        do { try trash(url) } catch { throw SquidExportError.failed("Could not move \(url.lastPathComponent) to the Trash: \(error.localizedDescription)") }
    }

    /// Takes the sample out of one channel of a bank (the channel folder goes to the Trash).
    public static func trashSample(set: String?, number: Int, slot: Int, volume: URL, trash: Trash = moveToTrash,
                                   fileManager fm: FileManager = .default) throws {
        guard let bank = SquidStick.bankURL(set: set, number: number, volume: volume, fileManager: fm) else {
            throw SquidExportError.missing(SquidLayout.bankFolder(number: number))
        }
        let targets = [bank.appendingPathComponent(String(slot), isDirectory: true)]
            + ((try? fm.contentsOfDirectory(atPath: bank.path)) ?? []).filter { SquidLayout.legacySlot(fromFileName: $0) == slot }.map { bank.appendingPathComponent($0) }
        do { for url in targets where fm.fileExists(atPath: url.path) { try trash(url) } }
        catch { throw SquidExportError.failed("Could not move the sample to the Trash: \(error.localizedDescription)") }
    }

    // MARK: pool

    /// Moves a sample, or a whole folder with its samples, from the Pool to the Trash. `path` runs from the Pool down
    /// ("Breaks", "707.wav"); it can never name the Pool itself or anything outside it.
    public static func trashPoolEntry(_ path: [String], volume: URL, trash: Trash = moveToTrash,
                                      fileManager fm: FileManager = .default) throws {
        guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            throw SquidExportError.invalid("That is not a sample or folder inside the Pool.")
        }
        guard let pool = SquidStick.poolURL(volume: volume, fileManager: fm) else { throw SquidExportError.missing(SquidLayout.poolFolder) }
        let url = path.reduce(pool) { $0.appendingPathComponent($1) }
        guard fm.fileExists(atPath: url.path) else { throw SquidExportError.missing(([SquidLayout.poolFolder] + path).joined(separator: "/")) }
        do { try trash(url) } catch { throw SquidExportError.failed("Could not move \(url.lastPathComponent) to the Trash: \(error.localizedDescription)") }
    }

    // MARK: helpers

    /// A set's folder (or the ALM022 folder for the default set); a new set's folder is made when `create` is set.
    private static func containerURL(set: String?, volume: URL, create: Bool, fileManager fm: FileManager) throws -> URL {
        guard let set else { return SquidStick.rootURL(volume: volume) }
        if let url = SquidStick.setURL(named: set, volume: volume, fileManager: fm) { return url }
        guard create else { throw SquidExportError.missing("Set \(set)") }
        if let problem = SquidLayout.check(setName: set).blockers.first { throw SquidExportError.invalid(problem) }
        return SquidStick.rootURL(volume: volume).appendingPathComponent(SquidLayout.setPrefix + set, isDirectory: true)
    }

    private static func writeName(_ name: String, to bank: URL) throws {
        try Data(SquidLayout.infoContents(name: name).utf8).write(to: bank.appendingPathComponent(SquidLayout.infoFile), options: .atomic)
    }

    /// Moves a folder. A change of case only ("Loops" to "loops") goes through a temporary name, as the stick is case-insensitive.
    private static func move(_ source: URL, to destination: URL, fileManager fm: FileManager) throws {
        let caseOnly = source.lastPathComponent.caseInsensitiveCompare(destination.lastPathComponent) == .orderedSame
            && source.deletingLastPathComponent() == destination.deletingLastPathComponent()
        if !caseOnly, fm.fileExists(atPath: destination.path) { throw SquidExportError.exists(destination.lastPathComponent) }
        do {
            if caseOnly {
                let temporary = source.deletingLastPathComponent().appendingPathComponent(".renaming-" + UUID().uuidString)
                try fm.moveItem(at: source, to: temporary)
                try fm.moveItem(at: temporary, to: destination)
            } else {
                try fm.moveItem(at: source, to: destination)
            }
        } catch { throw SquidExportError.failed(error.localizedDescription) }
    }
}
