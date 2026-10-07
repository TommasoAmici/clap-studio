import ClapCore
import Foundation

/// The real on-disk folder structure, shown as a tree. Purely a view: files are never moved.
struct FolderNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String           // relative to root, with trailing slash ("" for the root itself)
    let rootID: Int64
    var count: Int
    var children: [FolderNode]?

    static func build(roots: [RootRecord], samples: [SampleRecord]) -> [FolderNode] {
        final class Builder {
            var name: String, path: String, rootID: Int64, count = 0
            var kids: [String: Builder] = [:]
            init(name: String, path: String, rootID: Int64) { self.name = name; self.path = path; self.rootID = rootID }
            func node() -> FolderNode {
                let sorted = kids.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return FolderNode(id: "\(rootID)|\(path)", name: name, path: path, rootID: rootID, count: count,
                                  children: sorted.isEmpty ? nil : sorted.map { $0.node() })
            }
        }
        var builders: [Int64: Builder] = [:]
        for root in roots {
            builders[root.id] = Builder(name: (root.path as NSString).lastPathComponent, path: "", rootID: root.id)
        }
        for s in samples {
            guard let rootBuilder = builders[s.rootID] else { continue }
            rootBuilder.count += 1
            var node = rootBuilder
            var path = ""
            for part in s.folder.split(separator: "/") {
                path += part + "/"
                let child = node.kids[String(part)] ?? Builder(name: String(part), path: path, rootID: s.rootID)
                node.kids[String(part)] = child
                child.count += 1
                node = child
            }
        }
        return roots.compactMap { builders[$0.id]?.node() }
    }

    static func find(_ id: String, in nodes: [FolderNode]) -> FolderNode? {
        for n in nodes {
            if n.id == id { return n }
            if let hit = find(id, in: n.children ?? []) { return hit }
        }
        return nil
    }
}
