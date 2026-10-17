import Foundation

/// A folder inside the Pool of a stick, with the folders inside it.
public struct SquidPoolFolder: Identifiable, Equatable, Sendable {
    public let name: String
    /// From the Pool down, e.g. ["Breaks", "707"].
    public let path: [String]
    /// Samples directly in this folder, not counting the ones in its sub-folders.
    public let sampleCount: Int
    public var children: [SquidPoolFolder]

    public var id: String { path.joined(separator: "/") }
    /// Samples in this folder and every folder below it.
    public var totalSampleCount: Int { sampleCount + children.reduce(0) { $0 + $1.totalSampleCount } }

    public init(name: String, path: [String], sampleCount: Int, children: [SquidPoolFolder] = []) {
        self.name = name; self.path = path; self.sampleCount = sampleCount; self.children = children
    }
}

extension SquidStickContents {
    /// Every Pool folder as a path, each folder before the folders inside it.
    public var poolFolderPaths: [[String]] {
        func walk(_ folders: [SquidPoolFolder]) -> [[String]] { folders.flatMap { [$0.path] + walk($0.children) } }
        return walk(poolFolders)
    }

    /// The Pool folder at `path`, if it is there (names are matched without regard to case, as on the stick).
    public func poolFolder(at path: [String]) -> SquidPoolFolder? {
        var level = poolFolders
        var found: SquidPoolFolder?
        for part in path {
            guard let next = level.first(where: { $0.name.caseInsensitiveCompare(part) == .orderedSame }) else { return nil }
            found = next; level = next.children
        }
        return found
    }
}

extension SquidStick {
    /// How deep Pool folders are followed: the module browses only a few levels, and this keeps an odd stick from stalling the scan.
    static let maxPoolDepth = 8

    /// The folders of the Pool, sorted by name, with how many samples each holds.
    static func poolFolders(in pool: URL, fileManager fm: FileManager) -> [SquidPoolFolder] {
        folders(in: pool, path: [], fileManager: fm)
    }

    private static func folders(in folder: URL, path: [String], fileManager fm: FileManager) -> [SquidPoolFolder] {
        guard path.count < maxPoolDepth else { return [] }
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let name = url.lastPathComponent
                let inside = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles])) ?? []
                let samples = inside.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }.count
                return SquidPoolFolder(name: name, path: path + [name], sampleCount: samples,
                                       children: folders(in: url, path: path + [name], fileManager: fm))
            }
    }
}
