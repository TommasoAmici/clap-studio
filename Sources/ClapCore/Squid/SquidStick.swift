import Foundation

public struct SquidBank: Identifiable, Equatable, Sendable {
    public let set: String?        // nil for the default set
    public let number: Int
    public let name: String        // from info.txt, may be empty
    public let filledSlots: Int    // channel folders that hold a file
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

    public init(hasSquidFolder: Bool = false, sets: [SquidSet] = [], hasPool: Bool = false) {
        self.hasSquidFolder = hasSquidFolder; self.sets = sets; self.hasPool = hasPool
    }

    public var namedSetCount: Int { sets.filter { $0.name != nil }.count }

    public func set(named name: String?) -> SquidSet? { sets.first { $0.name == name } }

    /// Banks 1...99 of a set that do not exist yet, lowest first.
    public func freeBankNumbers(inSet name: String?) -> [Int] {
        let used = Set(set(named: name)?.banks.map(\.number) ?? [])
        return (1...SquidLayout.maxBanksPerSet).filter { !used.contains($0) }
    }
}

public enum SquidStick {
    public static func rootURL(volume: URL) -> URL { volume.appendingPathComponent(SquidLayout.rootFolder, isDirectory: true) }

    /// Reads the sets and banks of the stick mounted at `volume`.
    public static func read(volume: URL, fileManager fm: FileManager = .default) -> SquidStickContents {
        let root = rootURL(volume: volume)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return SquidStickContents() }
        var contents = SquidStickContents(hasSquidFolder: true)
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        let folders = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        contents.hasPool = folders.contains { $0.lastPathComponent.caseInsensitiveCompare(SquidLayout.poolFolder) == .orderedSame }

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
            return SquidBank(set: set, number: number, name: bankName(at: url), filledSlots: filledSlots(in: url, fileManager: fm))
        }
        .sorted { $0.number < $1.number }
    }

    /// The first line of info.txt, as the module would show it.
    static func bankName(at bank: URL) -> String {
        guard let data = try? Data(contentsOf: bank.appendingPathComponent(SquidLayout.infoFile)),
              let text = String(data: data.prefix(64), encoding: .utf8) ?? String(data: data.prefix(64), encoding: .isoLatin1)
        else { return "" }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.unicodeScalars.filter { $0.isASCII && !CharacterSet.controlCharacters.contains($0) }.prefix(SquidLayout.maxNameLength).map(Character.init))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func filledSlots(in bank: URL, fileManager fm: FileManager) -> Int {
        (1...SquidLayout.slotsPerBank).filter { slot in
            let dir = bank.appendingPathComponent(String(slot), isDirectory: true)
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            return files.contains { !$0.hasPrefix(".") && $0.lowercased().hasSuffix(".wav") }
        }.count
    }
}
