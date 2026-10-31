import Foundation

/// Joins sounds with the ALM Squid Salmple limits and puts the joined files on one channel of following banks:
/// 20 kicks might become 8, 8 and 4 sounds on channel 1 of banks 1, 2 and 3. A channel that already holds a sample is
/// overwritten (the sheet warned about it).
public enum SquidJoinedSender {
    /// Returns the bank and channel each joined file went to. The joined files are made in a temporary folder inside
    /// `workFolder` and removed again; library files are only read, and nothing reaches the stick unless every
    /// joined file has a place.
    @discardableResult
    public static func send(_ sources: [JoinSource], name: String, channel: Int, set: String?, firstBank: Int, bankName: String,
                            category: String?, toVolume volume: URL, workFolder: URL = FileManager.default.temporaryDirectory,
                            fileManager fm: FileManager = .default) throws -> [SquidSlot] {
        guard !sources.isEmpty else { throw SquidExportError.invalid("Add at least one sample.") }
        guard (1...SquidLayout.slotsPerBank).contains(channel) else {
            throw SquidExportError.invalid("A bank has channels 1 to \(SquidLayout.slotsPerBank).")
        }
        let work = workFolder.appendingPathComponent("clap-squid-join-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        let outputs = try JoinExporter.exportWithRegions(sources, settings: .almSalmple, name: name, to: work)

        let filled = Dictionary(uniqueKeysWithValues: (SquidStick.read(volume: volume, fileManager: fm).set(named: set)?.banks ?? [])
            .map { ($0.number, $0.filled) })
        let plan = SquidChannelPlan.make(overrides: Array(repeating: nil, count: outputs.count), rule: .sameChannel(channel),
                                         startBank: firstBank, filled: filled)
        if let blocking = plan.issues.first(where: \.isBlocking) {
            throw SquidExportError.invalid("Joining makes \(outputs.count) \(outputs.count == 1 ? "file" : "files"). "
                                           + blocking.message + " Nothing was sent.")
        }
        let slots = plan.slots.compactMap { $0 }
        let placed = zip(outputs, slots).map { output, slot in
            SquidPlacedSource(source: SquidSource(file: output.url, name: output.url.deletingPathExtension().lastPathComponent,
                                                  category: category, keepAudio: true), slot: slot)
        }
        try SquidExporter.place(placed, set: set, bankNames: Dictionary(uniqueKeysWithValues: slots.map { ($0.bank, bankName) }),
                                toVolume: volume, overwrite: true, fileManager: fm)
        return slots
    }
}
