import Foundation

public enum CollectionError: Error, LocalizedError, Equatable {
    case tooDeep
    case missingParent

    public var errorDescription: String? {
        switch self {
        case .tooDeep: return "A collection can hold sub-collections one level deep. A sub-collection cannot have its own, and a collection with sub-collections cannot go inside another."
        case .missingParent: return "That collection no longer exists."
        }
    }
}

/// A collection with everything needed to put it back after a delete: its sub-collections and its samples, in order.
public struct CollectionBackup: Sendable {
    public struct Member: Sendable { public var sampleID: Int64; public var added: Double }
    public var name: String
    public var parentID: Int64?
    public var created: Double
    public var members: [Member]
    public var children: [CollectionBackup]
}

/// One level of sub-collections: "Party #23" holding "Opening" and "Peak". Picking a collection shows its own samples and those of its
/// sub-collections. Everything lives in the index; audio files are never touched.
extension LibraryStore {
    /// The parent of a collection: nil outside when the collection does not exist, nil inside when it is at the top level.
    func parentOf(_ id: Int64) throws -> Int64?? {
        let rows = try db.query("SELECT parent_id FROM collections WHERE id = ?", [.int(id)]) { $0.isNull(0) ? Int64?.none : Int64?.some($0.int(0)) }
        return rows.first
    }

    public func subCollectionIDs(of id: Int64) -> [Int64] {
        (try? db.query("SELECT id FROM collections WHERE parent_id = ? ORDER BY id", [.int(id)]) { $0.int(0) }) ?? []
    }

    /// Puts a collection inside another (or back at the top level with nil), keeping to one level of nesting.
    public func setParent(of id: Int64, to parentID: Int64?) throws {
        if let parentID {
            guard parentID != id else { throw CollectionError.tooDeep }
            guard let parent = try parentOf(parentID) else { throw CollectionError.missingParent }
            guard parent == nil, subCollectionIDs(of: id).isEmpty else { throw CollectionError.tooDeep }
        }
        try db.run("UPDATE collections SET parent_id = ? WHERE id = ?", [parentID.map { .int($0) } ?? .null, .int(id)])
    }

    /// The samples you see on picking a collection: its own, then its sub-collections', each once.
    public func collectionTreeMembers(id: Int64) -> [Int64] {
        var seen = Set<Int64>()
        var result: [Int64] = []
        for collection in [id] + subCollectionIDs(of: id) {
            for sample in collectionMembers(id: collection) where seen.insert(sample).inserted { result.append(sample) }
        }
        return result
    }

    public func collectionBackup(id: Int64) -> CollectionBackup? {
        let rows = (try? db.query("SELECT name, parent_id, created FROM collections WHERE id = ?", [.int(id)]) { row in
            (row.text(0), row.isNull(1) ? Int64?.none : Int64?.some(row.int(1)), row.double(2))
        }) ?? []
        guard let row = rows.first else { return nil }
        let members = ((try? db.query("SELECT sample_id, added FROM collection_items WHERE collection_id = ? ORDER BY added, rowid",
                                      [.int(id)]) { CollectionBackup.Member(sampleID: $0.int(0), added: $0.double(1)) }) ?? [])
        return CollectionBackup(name: row.0, parentID: row.1, created: row.2, members: members,
                                children: subCollectionIDs(of: id).compactMap { collectionBackup(id: $0) })
    }

    /// Makes the collection (and its sub-collections) again with new ids. It goes back inside its old parent when that still exists.
    @discardableResult
    public func restoreCollection(_ backup: CollectionBackup, under parentID: Int64? = nil) throws -> CollectionRecord {
        let wanted = parentID ?? backup.parentID
        let parent = try wanted.flatMap { try parentOf($0) == .some(nil) ? $0 : nil }
        let record = try createCollection(name: backup.name, parentID: parent, at: Date(timeIntervalSince1970: backup.created))
        try db.transaction {
            for member in backup.members {
                try db.run("INSERT OR IGNORE INTO collection_items(collection_id, sample_id, added) VALUES(?, ?, ?)",
                           [.int(record.id), .int(member.sampleID), .double(member.added)])
            }
        }
        for child in backup.children { try restoreCollection(child, under: record.id) }
        return record
    }
}

/// A collection in the sidebar tree.
public struct CollectionNode: Identifiable, Hashable, Sendable {
    public let record: CollectionRecord
    /// nil when there are none, so a plain collection shows no disclosure arrow.
    public let children: [CollectionNode]?
    public var id: Int64 { record.id }

    /// Top-level collections by name, each holding its sub-collections by name. A sub-collection whose parent is missing is shown at the top.
    public static func tree(_ records: [CollectionRecord]) -> [CollectionNode] {
        let known = Set(records.map(\.id))
        func byName(_ list: [CollectionRecord]) -> [CollectionRecord] {
            list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return byName(records.filter { $0.parentID == nil || !known.contains($0.parentID!) }).map { top in
            let kids = byName(records.filter { $0.parentID == top.id }).map { CollectionNode(record: $0, children: nil) }
            return CollectionNode(record: top, children: kids.isEmpty ? nil : kids)
        }
    }

    /// Every collection in menu order, sub-collections titled "Parent › Child".
    public static func menuEntries(_ tree: [CollectionNode]) -> [(id: Int64, title: String)] {
        tree.flatMap { node -> [(id: Int64, title: String)] in
            [(node.record.id, node.record.name)] + (node.children ?? []).map { ($0.record.id, node.record.name + " › " + $0.record.name) }
        }
    }
}
