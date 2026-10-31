import Foundation

/// Replaces samples that are already on a stick without ever leaving a channel empty or half written. Each new sample
/// is first written as a clone next to the old one and checked byte for byte; only then are the old and new folders
/// swapped by renaming (one quick step each), and every step can be undone if a later one fails.
struct SquidOverwrite {
    let token = String(UUID().uuidString.prefix(8))
    private let fm: FileManager
    private var prepared: [(final: URL, clone: URL, old: [URL])] = []
    private var moves: [(from: URL, to: URL)] = []     // renames done so far, oldest first
    private var scratch: [URL] = []                    // hidden folders made on the stick, removed at the end

    init(fileManager fm: FileManager) { self.fm = fm }

    var isEmpty: Bool { prepared.isEmpty }

    /// Writes and checks a clone of `file` for `channelFolder`. `oldItems` are what the channel holds now (the folder,
    /// or a loose `Chan-00N.wav` of older firmware). Nothing that is on the stick yet is touched.
    mutating func prepare(file: URL, channelFolder: URL, oldItems: [URL]) throws {
        let clone = channelFolder.deletingLastPathComponent()
            .appendingPathComponent(".clap-new-\(token)-\(channelFolder.lastPathComponent)", isDirectory: true)
        scratch.append(clone)
        try fm.createDirectory(at: clone, withIntermediateDirectories: true)
        let copy = clone.appendingPathComponent(file.lastPathComponent)
        try fm.copyItem(at: file, to: copy)
        guard fm.contentsEqual(atPath: file.path, andPath: copy.path) else {
            throw SquidExportError.failed("The copy of \(file.lastPathComponent) on the stick did not match, so nothing was replaced.")
        }
        prepared.append((channelFolder, clone, oldItems))
    }

    /// Moves each old sample aside and puts its clone in its place. On a failure, call `rollback()`.
    mutating func commit() throws {
        var graves = Set<URL>()
        for item in prepared {
            let bank = item.final.deletingLastPathComponent()
            if !item.old.isEmpty {
                let grave = bank.appendingPathComponent(".clap-old-\(token)", isDirectory: true)
                if graves.insert(grave).inserted {
                    scratch.append(grave)
                    try fm.createDirectory(at: grave, withIntermediateDirectories: true)
                }
                for (index, old) in item.old.enumerated() {
                    try move(old, to: grave.appendingPathComponent("\(item.final.lastPathComponent)-\(index)-\(old.lastPathComponent)"))
                }
            }
            try move(item.clone, to: item.final)
        }
    }

    /// Puts every old sample back where it was and removes the clones.
    func rollback() {
        for step in moves.reversed() { try? fm.moveItem(at: step.to, to: step.from) }
        finish()
    }

    /// Removes the hidden folders: the clones that were not used and the samples that were replaced.
    func finish() { scratch.forEach { try? fm.removeItem(at: $0) } }

    private mutating func move(_ source: URL, to destination: URL) throws {
        try fm.moveItem(at: source, to: destination)
        moves.append((source, destination))
    }
}
