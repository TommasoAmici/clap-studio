import Foundation

/// Writes a `SquidCollectionPlan` to a stick. A bank set is written by `SquidExporter.place`, which writes all banks or none.
/// Pool folders are new ones, so if a later one fails the folder made so far is removed again.
public enum SquidCollectionSender {
    /// `sources` holds the sample to convert for every id in the plan. Library files are only read.
    public static func send(_ plan: SquidCollectionPlan, sources: [Int64: SquidSource], toVolume volume: URL,
                            fileManager fm: FileManager = .default) throws {
        guard !plan.isBlocked else { throw SquidExportError.invalid(plan.blockers.first ?? "There is nothing to send.") }
        func source(_ id: Int64) throws -> SquidSource {
            guard let found = sources[id] else { throw SquidExportError.missing("A sample of this collection") }
            return found
        }
        switch plan.destination {
        case .none: return
        case .set(let name, let banks):
            var placed: [SquidPlacedSource] = []
            for bank in banks {
                for (index, id) in bank.samples.enumerated() {
                    placed.append(SquidPlacedSource(source: try source(id), slot: SquidSlot(bank: bank.number, channel: index + 1)))
                }
            }
            try SquidExporter.place(placed, set: name, bankNames: Dictionary(uniqueKeysWithValues: banks.map { ($0.number, $0.name) }),
                                    toVolume: volume, fileManager: fm)
        case .pool(let groups):
            let ready = try groups.map { group in (group.path.joined(separator: "/"), try group.samples.map(source)) }
            var top: URL?
            do {
                for (path, group) in ready {
                    if top == nil, let first = path.split(separator: "/").first {
                        top = SquidStick.poolFolder(typed: String(first), volume: volume, fileManager: fm).url
                    }
                    try SquidExporter.exportToPool(group, subfolder: path, toVolume: volume, fileManager: fm)
                }
            } catch {
                if let top { try? fm.removeItem(at: top) }
                throw error
            }
        }
    }
}
