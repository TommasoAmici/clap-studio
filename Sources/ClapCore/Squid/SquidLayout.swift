import Foundation

/// The folder conventions of the ALM Squid Salmple (busycircuits.com/pages/alm022, manual "Saving & loading Banks"):
///
///     /ALM022/                      top level of a FAT32 stick
///         Bank 1/ … Bank 99/        the default bank set (a bank is 8 samples)
///             info.txt              bank name, first 8 ASCII characters
///             1/ … 8/               one folder per channel, holding one named .wav
///         Set NAME/                 more bank sets (NAME up to 8 characters, up to 16 sets)
///             Bank 1/ … Bank 99/
///         Pool/                     "load only" folder of loose samples and sub-folders (256 entries each)
public enum SquidLayout {
    public static let rootFolder = "ALM022"
    public static let poolFolder = "Pool"
    public static let setPrefix = "Set "
    public static let bankPrefix = "Bank "
    public static let infoFile = "info.txt"

    public static let slotsPerBank = 8
    public static let maxBanksPerSet = 99
    public static let maxSets = 16
    public static let maxNameLength = 8            // what the module's display shows
    public static let maxSetNameLength = 8
    public static let maxFileStemLength = 24
    public static let maxSeconds = 11.0            // longer samples are truncated by the module
    public static let sampleRate = 44_100.0        // other rates are ignored by the module
    public static let maxEntriesPerFolder = 256

    /// Audio is stored as 16-bit, 44.1 kHz, mono: what the module plays natively.
    public static let exportFormat = ExportFormat(bitDepth: .int16, mono: true, sampleRate: sampleRate)

    // MARK: locations

    public enum Location: Equatable, Sendable {
        /// A sample in a bank. `set` is nil for the default set; `slot` is 1...8 when known.
        case bank(set: String?, number: Int, slot: Int?)
        /// A sample in the Pool, with its sub-folders.
        case pool(folders: [String])
        case other
    }

    /// Where a file sits, from its path relative to the `ALM022` folder.
    public static func location(ofRelativePath path: String) -> Location {
        var parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return .other }
        if parts[0].caseInsensitiveCompare(poolFolder) == .orderedSame {
            return .pool(folders: Array(parts.dropFirst().dropLast()))
        }
        var set: String?
        if let name = setName(fromFolder: parts[0]) { set = name; parts.removeFirst() }
        guard let first = parts.first, let number = bankNumber(fromFolder: first) else { return .other }
        parts.removeFirst()
        // "3/Name.wav" is channel 3; a loose "Chan-003.wav" is the older layout for the same thing.
        if parts.count == 2, let slot = Int(parts[0]), (1...slotsPerBank).contains(slot) { return .bank(set: set, number: number, slot: slot) }
        if parts.count == 1, let slot = legacySlot(fromFileName: parts[0]) { return .bank(set: set, number: number, slot: slot) }
        return .bank(set: set, number: number, slot: nil)
    }

    /// Folder names are matched without regard to case: the stick is FAT32, which does not tell "Bank 1" and "bank 1" apart.
    private static func hasPrefix(_ name: String, _ prefix: String) -> Bool {
        name.count >= prefix.count && name.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
    }

    public static func bankNumber(fromFolder name: String) -> Int? {
        guard hasPrefix(name, bankPrefix), let n = Int(name.dropFirst(bankPrefix.count).trimmingCharacters(in: .whitespaces)),
              (1...maxBanksPerSet).contains(n) else { return nil }
        return n
    }

    /// The set a folder holds, with its name exactly as it is on the stick.
    public static func setName(fromFolder name: String) -> String? {
        guard hasPrefix(name, setPrefix) else { return nil }
        let rest = String(name.dropFirst(setPrefix.count))
        return rest.isEmpty ? nil : rest
    }

    /// Whether two set names (nil is the default set) are the same folder.
    public static func sameSet(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a?, let b?): return a.caseInsensitiveCompare(b) == .orderedSame
        default: return false
        }
    }

    static func legacySlot(fromFileName name: String) -> Int? {
        let lower = name.lowercased()
        guard lower.hasPrefix("chan-"), lower.hasSuffix(".wav"),
              let n = Int(lower.dropFirst(5).dropLast(4)), (1...slotsPerBank).contains(n) else { return nil }
        return n
    }

    // MARK: folder names

    public static func bankFolder(number: Int) -> String { "\(bankPrefix)\(number)" }

    /// "Set NAME", with the name exactly as given. nil when a folder cannot have that name (see `check(setName:)`).
    public static func setFolder(name: String) -> String? {
        check(setName: name).isBlocked ? nil : setPrefix + name
    }

    /// Path of a bank folder below the `ALM022` folder: "Bank 3" or "Set Loops/Bank 3".
    public static func bankPath(set: String?, number: Int) -> String? {
        guard (1...maxBanksPerSet).contains(number) else { return nil }
        if let set {
            guard let folder = setFolder(name: set) else { return nil }
            return "\(folder)/\(bankFolder(number: number))"
        }
        return bankFolder(number: number)
    }

    // MARK: names

    static let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_")

    static func reduce(_ text: String, to allowed: CharacterSet) -> String {
        // Fold accents to plain letters first ("Café" becomes "Cafe"), then keep safe characters only.
        let folded = text.folding(options: [.diacriticInsensitive], locale: nil)
        let kept = folded.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
    }

    /// A file name (without extension) that is safe on a FAT32 stick. The module shows the first 8 characters.
    public static func cleanFileStem(_ raw: String, fallback: String = "Sample") -> String {
        let stem = String(reduce(raw, to: plain).prefix(maxFileStemLength)).trimmingCharacters(in: .whitespaces)
        return stem.isEmpty ? fallback : stem
    }

    /// Contents of a bank's info.txt: the name as typed.
    public static func infoContents(name: String) -> String { name + "\n" }
}
