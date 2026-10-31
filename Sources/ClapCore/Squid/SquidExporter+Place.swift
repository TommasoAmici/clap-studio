import Foundation

/// A sample and the bank channel it goes to.
public struct SquidPlacedSource: Sendable {
    public var source: SquidSource
    public var slot: SquidSlot
    public init(source: SquidSource, slot: SquidSlot) { self.source = source; self.slot = slot }
}

extension SquidExporter {
    /// Writes samples to the exact channels given, across any number of banks of one set. A bank that is not on the stick
    /// is made (named from `bankNames`); a bank that is there keeps its name and samples. A channel that is given twice
    /// stops the whole send before anything is written, and so does one that already holds a sample unless `overwrite` is
    /// set: then that sample is replaced through `SquidOverwrite` (cloned and checked first, so a bank is never left half
    /// written). A failure part way removes what this call wrote and puts replaced samples back.
    public static func place(_ placed: [SquidPlacedSource], set: String?, bankNames: [Int: String], toVolume volume: URL,
                             overwrite: Bool = false, fileManager fm: FileManager = .default) throws {
        guard !placed.isEmpty else { throw SquidExportError.invalid("Add at least one sample.") }
        if let set, let problem = SquidLayout.check(setName: set).blockers.first { throw SquidExportError.invalid(problem) }
        var seen = Set<SquidSlot>()
        for item in placed {
            guard (1...SquidLayout.maxBanksPerSet).contains(item.slot.bank) else {
                throw SquidExportError.invalid("Choose a bank from 1 to \(SquidLayout.maxBanksPerSet).")
            }
            guard (1...SquidLayout.slotsPerBank).contains(item.slot.channel) else {
                throw SquidExportError.invalid("A bank has channels 1 to \(SquidLayout.slotsPerBank).")
            }
            guard seen.insert(item.slot).inserted else {
                throw SquidExportError.invalid("Two samples were given channel \(item.slot.channel) of bank \(item.slot.bank).")
            }
        }
        try requireVolume(volume, fileManager: fm)

        // Banks and channels that are already there are only read.
        var existing: [Int: URL] = [:]
        var taken: [Int: Set<Int>] = [:]            // channels that hold a sample now, by bank
        for bank in Set(placed.map(\.slot.bank)) {
            guard let url = SquidStick.bankURL(set: set, number: bank, volume: volume, fileManager: fm) else { continue }
            existing[bank] = url
            let filled = SquidStick.filledSlotNumbers(in: url, fileManager: fm)
            taken[bank] = filled
            if !overwrite, let clash = placed.first(where: { $0.slot.bank == bank && filled.contains($0.slot.channel) }) {
                throw SquidExportError.exists("Channel \(clash.slot.channel) of "
                                              + (SquidLayout.bankPath(set: set, number: bank) ?? "that bank"))
            }
        }
        let setURL = set.flatMap { SquidStick.setURL(named: $0, volume: volume, fileManager: fm) }
        if set != nil, setURL == nil, SquidStick.read(volume: volume, fileManager: fm).namedSetCount >= SquidLayout.maxSets {
            throw SquidExportError.tooManySets
        }

        // Convert everything first, so a file that fails leaves the stick untouched.
        let staging = fm.temporaryDirectory.appendingPathComponent("clap-squid-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        var staged: [(slot: SquidSlot, file: URL)] = []
        var bytes: Int64 = 0
        for (index, item) in placed.enumerated() {
            let folder = staging.appendingPathComponent(String(index), isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(SquidLayout.cleanFileStem(item.source.name) + ".wav")
            do {
                if item.source.keepAudio {
                    try fm.copyItem(at: item.source.file, to: target)
                } else {
                    try TrimExporter.write(source: item.source.file, trim: item.source.trim, format: SquidLayout.exportFormat, to: target,
                                           maxSeconds: SquidLayout.maxSeconds, declick: true, matchLevel: item.source.matchLevel)
                }
            } catch { throw SquidExportError.failed("\(item.source.file.lastPathComponent): \(error.localizedDescription)") }
            tag(target, with: item.source.category)
            bytes += fileSize(target) + 4096
            staged.append((item.slot, target))
        }
        try requireSpace(bytes + Int64(Set(placed.map(\.slot.bank)).count) * 4096, volume: volume)

        let alm = SquidStick.rootURL(volume: volume)
        let container = setURL ?? alm.appendingPathComponent(set.flatMap(SquidLayout.setFolder(name:)) ?? "", isDirectory: true)
        var swap = SquidOverwrite(fileManager: fm)
        var created: [URL] = []          // what this call made, newest last, for taking it back out on failure
        do {
            if set != nil, setURL == nil {
                try fm.createDirectory(at: container, withIntermediateDirectories: true)
                created.append(container)
            }
            var bankURLs = existing
            for bank in Set(placed.map(\.slot.bank)).sorted() where bankURLs[bank] == nil {
                let url = (set == nil ? alm : container).appendingPathComponent(SquidLayout.bankFolder(number: bank), isDirectory: true)
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                created.append(url)
                try Data(SquidLayout.infoContents(name: bankNames[bank] ?? "").utf8).write(to: url.appendingPathComponent(SquidLayout.infoFile))
                bankURLs[bank] = url
            }
            for (slot, file) in staged {
                let bankURL = bankURLs[slot.bank]!
                let folder = bankURL.appendingPathComponent(String(slot.channel), isDirectory: true)
                if taken[slot.bank]?.contains(slot.channel) == true {
                    try swap.prepare(file: file, channelFolder: folder, oldItems: replacedItems(bank: bankURL, channel: slot.channel, fileManager: fm))
                    continue
                }
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                created.append(folder)
                try fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            try swap.commit()
        } catch {
            swap.rollback()
            created.reversed().forEach { try? fm.removeItem(at: $0) }
            throw SquidExportError.failed(error.localizedDescription)
        }
        swap.finish()
    }

    /// What a channel holds now: its folder, and a loose `Chan-00N.wav` of older firmware.
    private static func replacedItems(bank: URL, channel: Int, fileManager fm: FileManager) -> [URL] {
        var items: [URL] = []
        let folder = bank.appendingPathComponent(String(channel), isDirectory: true)
        if fm.fileExists(atPath: folder.path) { items.append(folder) }
        for name in (try? fm.contentsOfDirectory(atPath: bank.path)) ?? [] where SquidLayout.legacySlot(fromFileName: name) == channel {
            items.append(bank.appendingPathComponent(name))
        }
        return items
    }
}
