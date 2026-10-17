import Foundation

/// One line of the Pool as the main area shows it: a folder heading, or a sample.
public enum PoolRow<Item> {
    case folder(SquidPoolFolder, depth: Int, expanded: Bool)
    case sample(Item)
}

/// Lays the samples of a Pool (or of one Pool folder) out under their folders, which can be opened and closed.
public enum PoolOutline {
    /// Folders are told apart without regard to case, as on a FAT32 stick.
    public static func key(_ path: [String]) -> String { path.joined(separator: "/").lowercased() }

    /// The lines to show. The samples directly in `root` come first, then each folder with its samples and the folders
    /// inside it (unless it is in `collapsed`, which holds `key(path)` values). An empty folder still gets a line.
    /// `items` are in the order they should appear in; a sample in a folder that is not in `folders` goes at the end,
    /// so nothing is hidden when the stick changed after it was scanned.
    public static func rows<Item>(root: [String], folders: [SquidPoolFolder], items: [(folder: [String], item: Item)],
                                  collapsed: Set<String>) -> [PoolRow<Item>] {
        var byFolder: [String: [Item]] = [:]
        for entry in items { byFolder[key(entry.folder), default: []].append(entry.item) }

        var known: Set<String> = [key(root)]
        func learn(_ folders: [SquidPoolFolder]) { for folder in folders { known.insert(key(folder.path)); learn(folder.children) } }
        learn(folders)

        var rows: [PoolRow<Item>] = (byFolder[key(root)] ?? []).map { .sample($0) }
        func walk(_ folders: [SquidPoolFolder], depth: Int) {
            for folder in folders {
                let expanded = !collapsed.contains(key(folder.path))
                rows.append(.folder(folder, depth: depth, expanded: expanded))
                guard expanded else { continue }
                rows += (byFolder[key(folder.path)] ?? []).map { .sample($0) }
                walk(folder.children, depth: depth + 1)
            }
        }
        walk(folders, depth: 0)
        rows += items.filter { !known.contains(key($0.folder)) }.map { .sample($0.item) }
        return rows
    }
}

extension SquidLayout {
    /// Whether a file is in the Pool folder at `path` or anywhere below it (an empty path is the whole Pool).
    public static func location(_ location: Location, isInPoolFolder path: [String]) -> Bool {
        guard case .pool(let folders) = location, folders.count >= path.count else { return false }
        return zip(folders, path).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
    }
}
