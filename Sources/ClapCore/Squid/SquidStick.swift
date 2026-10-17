import Foundation

public struct SquidBank: Identifiable, Equatable, Sendable {
    public let set: String?        // nil for the default set
    public let number: Int
    public let name: String        // from info.txt, may be empty
    public let filled: Set<Int>    // channels (1...8) that hold a file
    public var filledSlots: Int { filled.count }
    /// How many more samples the bank can hold: 8 minus the ones it has.
    public var freeSlots: Int { max(0, SquidLayout.slotsPerBank - filledSlots) }
    /// The empty channels, lowest first.
    public var freeSlotNumbers: [Int] { (1...SquidLayout.slotsPerBank).filter { !filled.contains($0) } }

    public init(set: String?, number: Int, name: String, filled: Set<Int>) {
        self.set = set; self.number = number; self.name = name; self.filled = filled
    }
    public var id: String { "\(set ?? "")|\(number)" }
    public var folder: String { SquidLayout.bankPath(set: set, number: number) ?? SquidLayout.bankFolder(number: number) }
}

public struct SquidSet: Identifiable, Equatable, Sendable {
    public let name: String?       // nil for the default set
    public var banks: [SquidBank]
    public var id: String { name ?? "" }
    public var title: String { name ?? "Default" }
}

/// What is on a stick, read from folder names and info.txt files only (no audio is opened).
public struct SquidStickContents: Equatable, Sendable {
    public var hasSquidFolder = false
    public var sets: [SquidSet] = []
    public var hasPool = false
    /// The folders inside the Pool, with their sub-folders.
    public var poolFolders: [SquidPoolFolder] = []

    public init(hasSquidFolder: Bool = false, sets: [SquidSet] = [], hasPool: Bool = false, poolFolders: [SquidPoolFolder] = []) {
        self.hasSquidFolder = hasSquidFolder; self.sets = sets; self.hasPool = hasPool; self.poolFolders = poolFolders
    }

    public var namedSetCount: Int { sets.filter { $0.name != nil }.count }

    public func set(named name: String?) -> SquidSet? { sets.first { SquidLayout.sameSet($0.name, name) } }

    /// Banks 1...99 of a set that do not exist yet, lowest first.
    public func freeBankNumbers(inSet name: String?) -> [Int] {
        let used = Set(set(named: name)?.banks.map(\.number) ?? [])
        return (1...SquidLayout.maxBanksPerSet).filter { !used.contains($0) }
    }
}

public enum SquidStick {
    public static func rootURL(volume: URL) -> URL { volume.appendingPathComponent(SquidLayout.rootFolder, isDirectory: true) }

    /// A drive is for the module when it holds a folder named `ALM022` at its top level.
    public static func isForModule(volume: URL, fileManager fm: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: rootURL(volume: volume).path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Reads the sets and banks of the stick mounted at `volume`.
    public static func read(volume: URL, fileManager fm: FileManager = .default) -> SquidStickContents {
        let root = rootURL(volume: volume)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return SquidStickContents() }
        var contents = SquidStickContents(hasSquidFolder: true)
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        let folders = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if let pool = folders.first(where: { $0.lastPathComponent.caseInsensitiveCompare(SquidLayout.poolFolder) == .orderedSame }) {
            contents.hasPool = true
            contents.poolFolders = poolFolders(in: pool, fileManager: fm)
        }

        contents.sets = [SquidSet(name: nil, banks: banks(in: root, set: nil, fileManager: fm))]
        let named = folders.compactMap { url in SquidLayout.setName(fromFolder: url.lastPathComponent).map { ($0, url) } }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        for (name, url) in named { contents.sets.append(SquidSet(name: name, banks: banks(in: url, set: name, fileManager: fm))) }
        return contents
    }

    private static func banks(in folder: URL, set: String?, fileManager fm: FileManager) -> [SquidBank] {
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { url -> SquidBank? in
            guard let number = SquidLayout.bankNumber(fromFolder: url.lastPathComponent) else { return nil }
            return SquidBank(set: set, number: number, name: bankName(at: url), filled: filledSlotNumbers(in: url, fileManager: fm))
        }
        .sorted { $0.number < $1.number }
    }

    /// Where a set's folder is on the stick, whatever the case of its name.
    public static func setURL(named name: String, volume: URL, fileManager fm: FileManager = .default) -> URL? {
        let entries = (try? fm.contentsOfDirectory(at: rootURL(volume: volume), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.first { SquidLayout.setName(fromFolder: $0.lastPathComponent).map { SquidLayout.sameSet($0, name) } ?? false }
    }

    /// Where the Pool folder is, whatever the case of its name.
    public static func poolURL(volume: URL, fileManager fm: FileManager = .default) -> URL? {
        let entries = (try? fm.contentsOfDirectory(at: rootURL(volume: volume), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.first { $0.lastPathComponent.caseInsensitiveCompare(SquidLayout.poolFolder) == .orderedSame }
    }

    /// Where a bank's folder is, if it exists ("Bank 5" and "bank 05" are the same bank).
    public static func bankURL(set: String?, number: Int, volume: URL, fileManager fm: FileManager = .default) -> URL? {
        let container: URL
        if let set { guard let url = setURL(named: set, volume: volume, fileManager: fm) else { return nil }; container = url }
        else { container = rootURL(volume: volume) }
        let entries = (try? fm.contentsOfDirectory(at: container, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.first { SquidLayout.bankNumber(fromFolder: $0.lastPathComponent) == number }
    }

    /// The name in a bank's info.txt: its first line, as stored.
    static func bankName(at bank: URL) -> String {
        guard let data = try? Data(contentsOf: bank.appendingPathComponent(SquidLayout.infoFile)) else { return "" }
        let head = data.prefix(512)
        let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) ?? ""
        return String(text.prefix { !$0.isNewline })
    }

    /// Channels that hold a sample: a numbered folder with a .wav in it, or (older firmware) a loose `Chan-00x.wav`.
    static func filledSlotNumbers(in bank: URL, fileManager fm: FileManager) -> Set<Int> {
        var filled = Set<Int>()
        for slot in 1...SquidLayout.slotsPerBank {
            let files = (try? fm.contentsOfDirectory(atPath: bank.appendingPathComponent(String(slot), isDirectory: true).path)) ?? []
            if files.contains(where: { !$0.hasPrefix(".") && $0.lowercased().hasSuffix(".wav") }) { filled.insert(slot) }
        }
        for name in (try? fm.contentsOfDirectory(atPath: bank.path)) ?? [] {
            if let slot = SquidLayout.legacySlot(fromFileName: name) { filled.insert(slot) }
        }
        return filled
    }
}
