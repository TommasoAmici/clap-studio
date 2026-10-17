import AppKit
import ClapCore
import Foundation

/// The Pool, or one of its folders, as the main list shows it: the folders to draw headings for, and which are folded shut.
struct PoolLayout: Equatable {
    let drive: String
    /// The folder the list starts from, as a path inside the Pool (empty for the whole Pool).
    let root: [String]
    let folders: [SquidPoolFolder]
    let closed: Set<String>          // `PoolOutline.key` of each folder that is folded shut
}

extension AppModel {
    private func closedPoolKey(drive: String, path: [String]) -> String { drive + "|" + PoolOutline.key(path) }

    /// Set while the Pool, or a folder of it, is showing: the list then shows folders as headings with their samples under them.
    var poolLayout: PoolLayout? {
        guard showingUsb, let selection = usbSelection, let contents = usbContents[selection.drive], contents.hasPool else { return nil }
        let prefix = selection.drive + "|"
        let closed = Set(closedPoolFolders.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
        switch selection.area {
        case .pool: return PoolLayout(drive: selection.drive, root: [], folders: contents.poolFolders, closed: closed)
        case .poolFolder(let path):
            guard let folder = contents.poolFolder(at: path) else { return nil }
            return PoolLayout(drive: selection.drive, root: path, folders: folder.children, closed: closed)
        default: return nil
        }
    }

    /// Folds a Pool folder shut, or opens it again.
    func togglePoolFolder(drive: String, path: [String]) {
        let key = closedPoolKey(drive: drive, path: path)
        if closedPoolFolders.contains(key) { closedPoolFolders.remove(key) } else { closedPoolFolders.insert(key) }
    }

    /// Where a Pool folder is on the stick.
    func poolFolderURL(drive: String, path: [String]) -> URL? {
        guard let volume = self.drive(id: drive)?.url else { return nil }
        let pool = SquidStick.poolURL(volume: volume) ?? SquidStick.rootURL(volume: volume)
        return path.reduce(pool) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// The right-click menu of a folder heading in the list.
    func poolFolderMenu(drive: String, path: [String]) -> [SampleMenuEntry] {
        [
            .action("Send Samples Here…") { [unowned self] in
                openSquidExport(ids: actionTargets, drive: drive, pool: true, poolFolder: path.joined(separator: "/"))
            },
            .divider,
            .action("Reveal in Finder") { [unowned self] in
                if let url = poolFolderURL(drive: drive, path: path) { NSWorkspace.shared.open(url) }
            },
            .divider,
            .action("Move to Trash") { [unowned self] in trashPoolEntries([PoolEntry(drive: drive, path: path)]) },
        ]
    }
}
