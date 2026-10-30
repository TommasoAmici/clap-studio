import Foundation

/// One sample going into a bank slot or the Pool.
public struct SquidSource: Sendable {
    public var file: URL
    public var trim: SampleTrim?
    /// The name to give the file (a safe version is used on the stick).
    public var name: String
    /// Written into the file, so the stick keeps showing the sample under this category.
    public var category: String?
    /// Bring the sample to the app's common loudness, so every sample on the stick plays at a similar volume.
    public var matchLevel: Bool
    public init(file: URL, trim: SampleTrim? = nil, name: String, category: String? = nil, matchLevel: Bool = false) {
        self.file = file; self.trim = trim; self.name = name; self.category = category; self.matchLevel = matchLevel
    }
}

public struct SquidBankRequest: Sendable {
    public var set: String?
    public var number: Int
    public var name: String
    /// Eight slots in channel order; nil leaves a channel empty.
    public var slots: [SquidSource?]
    public var replaceExisting = false
    public init(set: String?, number: Int, name: String, slots: [SquidSource?], replaceExisting: Bool = false) {
        self.set = set; self.number = number; self.name = name; self.slots = slots; self.replaceExisting = replaceExisting
    }
}

public enum SquidExportError: Error, LocalizedError, Equatable {
    case invalid(String)
    case bankExists(String)
    case tooManySets
    case folderFull(String)
    case notEnoughSpace(needed: Int64, available: Int64)
    case exists(String)
    case missing(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let m): return m
        case .bankExists(let folder): return "\(folder) already exists on the stick."
        case .tooManySets: return "The module reads at most \(SquidLayout.maxSets) bank sets per stick."
        case .folderFull(let folder): return "\(folder) would hold more than \(SquidLayout.maxEntriesPerFolder) entries, which the module cannot browse."
        case .notEnoughSpace(let needed, let available):
            return "Not enough space on the stick (\(needed / 1024) KB needed, \(available / 1024) KB free)."
        case .exists(let what): return "\(what) already exists on the stick."
        case .missing(let what): return "\(what) is no longer on the stick."
        case .failed(let m): return m
        }
    }
}

/// Writes banks and Pool samples to a stick in the layout the Squid expects. Audio is converted to
/// 16-bit, 44.1 kHz mono and cut at 11 seconds. Existing files are never silently overwritten.
public enum SquidExporter {
    /// Writes one bank. Everything is converted in a temporary folder first, so a failing file leaves the stick untouched.
    @discardableResult
    public static func export(_ request: SquidBankRequest, toVolume volume: URL, fileManager fm: FileManager = .default) throws -> URL {
        if let set = request.set, let problem = SquidLayout.check(setName: set).blockers.first { throw SquidExportError.invalid(problem) }
        guard let bankPath = SquidLayout.bankPath(set: request.set, number: request.number) else {
            throw SquidExportError.invalid("Choose a bank from 1 to \(SquidLayout.maxBanksPerSet).")
        }
        guard request.slots.count <= SquidLayout.slotsPerBank else {
            throw SquidExportError.invalid("A bank holds \(SquidLayout.slotsPerBank) samples.")
        }
        guard request.slots.contains(where: { $0 != nil }) else { throw SquidExportError.invalid("Add at least one sample.") }
        try requireVolume(volume, fileManager: fm)

        let staging = fm.temporaryDirectory.appendingPathComponent("clap-squid-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        var staged: [(slot: Int, folder: URL)] = []
        var bytes: Int64 = 0
        for (index, source) in request.slots.enumerated() {
            guard let source else { continue }
            let slot = index + 1
            let folder = staging.appendingPathComponent(String(slot), isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(SquidLayout.cleanFileStem(source.name) + ".wav")
            do {
                try TrimExporter.write(source: source.file, trim: source.trim, format: SquidLayout.exportFormat, to: target,
                                       maxSeconds: SquidLayout.maxSeconds, declick: true, matchLevel: source.matchLevel)
            } catch { throw SquidExportError.failed("\(source.file.lastPathComponent): \(error.localizedDescription)") }
            tag(target, with: source.category)
            bytes += fileSize(target) + 4096
            staged.append((slot, folder))
        }
        try requireSpace(bytes, volume: volume)

        let alm = SquidStick.rootURL(volume: volume)
        if let set = request.set, SquidStick.setURL(named: set, volume: volume, fileManager: fm) == nil,
           SquidStick.read(volume: volume, fileManager: fm).namedSetCount >= SquidLayout.maxSets {
            throw SquidExportError.tooManySets
        }
        // An existing set or bank is written where it already is, whatever the case of its folder name.
        let existingBank = SquidStick.bankURL(set: request.set, number: request.number, volume: volume, fileManager: fm)
        let setURL = request.set.flatMap { SquidStick.setURL(named: $0, volume: volume, fileManager: fm) }
        let container = setURL ?? alm.appendingPathComponent(request.set.flatMap(SquidLayout.setFolder(name:)) ?? "", isDirectory: true)
        let bankURL = existingBank ?? (request.set == nil ? alm : container).appendingPathComponent(SquidLayout.bankFolder(number: request.number), isDirectory: true)
        if fm.fileExists(atPath: bankURL.path) {
            guard request.replaceExisting else { throw SquidExportError.bankExists(bankPath) }
            do { try fm.trashItem(at: bankURL, resultingItemURL: nil) }
            catch { throw SquidExportError.failed("Could not move the old \(bankPath) to the Trash (\(error.localizedDescription)). Remove it by hand and try again.") }
        }
        do {
            try fm.createDirectory(at: bankURL, withIntermediateDirectories: true)
            for (slot, folder) in staged {
                try fm.copyItem(at: folder, to: bankURL.appendingPathComponent(String(slot), isDirectory: true))
            }
            try Data(SquidLayout.infoContents(name: request.name).utf8).write(to: bankURL.appendingPathComponent(SquidLayout.infoFile))
        } catch {
            try? fm.removeItem(at: bankURL)
            throw SquidExportError.failed(error.localizedDescription)
        }
        return bankURL
    }

    /// Puts samples into the empty channels of a bank that is already on the stick, lowest channel first. Samples already in the
    /// bank are not touched. Returns the channels that were filled; samples beyond the free channels are left out.
    @discardableResult
    public static func add(_ sources: [SquidSource], set: String?, number: Int, toVolume volume: URL,
                           fileManager fm: FileManager = .default) throws -> [Int] {
        guard !sources.isEmpty else { throw SquidExportError.invalid("Add at least one sample.") }
        try requireVolume(volume, fileManager: fm)
        guard let bankURL = SquidStick.bankURL(set: set, number: number, volume: volume, fileManager: fm) else {
            throw SquidExportError.missing(SquidLayout.bankPath(set: set, number: number) ?? "That bank")
        }
        let free = (1...SquidLayout.slotsPerBank).filter { !SquidStick.filledSlotNumbers(in: bankURL, fileManager: fm).contains($0) }
        guard !free.isEmpty else { throw SquidExportError.invalid("This bank has no free channel.") }
        let chosen = Array(zip(free, sources))

        let staging = fm.temporaryDirectory.appendingPathComponent("clap-squid-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        var staged: [(slot: Int, file: URL)] = []
        var bytes: Int64 = 0
        for (slot, source) in chosen {
            let folder = staging.appendingPathComponent(String(slot), isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(SquidLayout.cleanFileStem(source.name) + ".wav")
            do {
                try TrimExporter.write(source: source.file, trim: source.trim, format: SquidLayout.exportFormat, to: target,
                                       maxSeconds: SquidLayout.maxSeconds, declick: true, matchLevel: source.matchLevel)
            } catch { throw SquidExportError.failed("\(source.file.lastPathComponent): \(error.localizedDescription)") }
            tag(target, with: source.category)
            bytes += fileSize(target) + 4096
            staged.append((slot, target))
        }
        try requireSpace(bytes, volume: volume)

        var written: [URL] = []
        do {
            for (slot, file) in staged {
                let folder = bankURL.appendingPathComponent(String(slot), isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(file.lastPathComponent)
                try fm.copyItem(at: file, to: target)
                written.append(target)
            }
        } catch {
            written.forEach { try? fm.removeItem(at: $0) }
            throw SquidExportError.failed(error.localizedDescription)
        }
        return chosen.map(\.0)
    }

    /// Writes loose samples into `Pool/` (or a sub-folder of it, e.g. "Breaks/707"). Never overwrites: a clash gets a number.
    @discardableResult
    public static func exportToPool(_ sources: [SquidSource], subfolder: String = "", toVolume volume: URL,
                                    fileManager fm: FileManager = .default) throws -> [URL] {
        guard !sources.isEmpty else { throw SquidExportError.invalid("Add at least one sample.") }
        try requireVolume(volume, fileManager: fm)
        let (folder, names) = SquidStick.poolFolder(typed: subfolder, volume: volume, fileManager: fm)
        let existing = (try? fm.contentsOfDirectory(atPath: folder.path))?.filter { !$0.hasPrefix(".") }.count ?? 0
        guard existing + sources.count <= SquidLayout.maxEntriesPerFolder else {
            throw SquidExportError.folderFull(names.joined(separator: "/"))
        }

        let staging = fm.temporaryDirectory.appendingPathComponent("clap-squid-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var staged: [URL] = []
        var bytes: Int64 = 0
        for (index, source) in sources.enumerated() {
            let target = staging.appendingPathComponent("\(index)-" + SquidLayout.cleanFileStem(source.name) + ".wav")
            do {
                try TrimExporter.write(source: source.file, trim: source.trim, format: SquidLayout.exportFormat, to: target,
                                       maxSeconds: SquidLayout.maxSeconds, declick: true, matchLevel: source.matchLevel)
            } catch { throw SquidExportError.failed("\(source.file.lastPathComponent): \(error.localizedDescription)") }
            tag(target, with: source.category)
            bytes += fileSize(target) + 4096
            staged.append(target)
        }
        try requireSpace(bytes, volume: volume)

        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        do {
            for (index, file) in staged.enumerated() {
                let name = SquidLayout.cleanFileStem(sources[index].name) + ".wav"
                let target = SampleExporter.uniqueURL(in: folder, fileName: name, fileManager: fm)
                try fm.copyItem(at: file, to: target)
                written.append(target)
            }
        } catch {
            written.forEach { try? fm.removeItem(at: $0) }
            throw SquidExportError.failed(error.localizedDescription)
        }
        return written
    }

    /// Keeps the category in the file. A sample that cannot take the tag is still a good sample, so this never fails the export.
    static func tag(_ file: URL, with category: String?) {
        guard let category, !category.isEmpty else { return }
        try? WavInfo.appendGenre(category, to: file)
    }

    // MARK: checks

    static func requireVolume(_ volume: URL, fileManager fm: FileManager) throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: volume.path, isDirectory: &isDir), isDir.boolValue else {
            throw SquidExportError.invalid("The USB stick is not available.")
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    static func requireSpace(_ needed: Int64, volume: URL) throws {
        guard let available = (try? volume.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity else { return }
        if Int64(available) < needed { throw SquidExportError.notEnoughSpace(needed: needed, available: Int64(available)) }
    }
}
