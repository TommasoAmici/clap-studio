import Foundation

public struct CollectionRecord: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String
    /// The samples you see on picking the collection: its own plus its sub-collections', each counted once.
    public var count: Int
    /// The samples put in this collection itself.
    public var ownCount: Int
    /// The collection this one sits inside, nil at the top level.
    public var parentID: Int64?

    public init(id: Int64, name: String, count: Int, ownCount: Int? = nil, parentID: Int64? = nil) {
        self.id = id; self.name = name; self.count = count; self.ownCount = ownCount ?? count; self.parentID = parentID
    }
}

/// Favorites and named collections. Both live in the index only; the files are never touched.
extension LibraryStore {
    public func setFavorite(_ ids: [Int64], _ favorite: Bool) throws {
        try db.transaction {
            for id in ids { try db.run("UPDATE samples SET favorite = ? WHERE id = ?", [.int(favorite ? 1 : 0), .int(id)]) }
        }
    }

    /// All collections, sorted by name; sub-collections are listed too (see `CollectionNode.tree`).
    public func collections() -> [CollectionRecord] {
        var records = (try? db.query("""
            SELECT c.id, c.name, COUNT(i.sample_id), c.parent_id FROM collections c
            LEFT JOIN collection_items i ON i.collection_id = c.id
            GROUP BY c.id ORDER BY c.name COLLATE NOCASE
            """) { CollectionRecord(id: $0.int(0), name: $0.text(1), count: Int($0.int(2)), parentID: $0.isNull(3) ? nil : $0.int(3)) }) ?? []
        for index in records.indices where records.contains(where: { $0.parentID == records[index].id }) {
            records[index].count = collectionTreeMembers(id: records[index].id).count
        }
        return records
    }

    @discardableResult
    public func createCollection(name: String, parentID: Int64? = nil, at date: Date = Date()) throws -> CollectionRecord {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parentID {
            guard let parent = try parentOf(parentID) else { throw CollectionError.missingParent }
            guard parent == nil else { throw CollectionError.tooDeep }
        }
        try db.run("INSERT INTO collections(name, created, parent_id) VALUES(?, ?, ?)",
                   [.text(clean.isEmpty ? "Untitled" : clean), .double(date.timeIntervalSince1970), parentID.map { .int($0) } ?? .null])
        let id = try db.scalarInt("SELECT MAX(id) FROM collections") ?? 0
        return CollectionRecord(id: id, name: clean.isEmpty ? "Untitled" : clean, count: 0, parentID: parentID)
    }

    public func renameCollection(id: Int64, to name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        try db.run("UPDATE collections SET name = ? WHERE id = ?", [.text(clean), .int(id)])
    }

    /// Deletes the collection and, if it has any, its sub-collections. The samples themselves are never touched.
    public func deleteCollection(id: Int64) throws {
        try db.transaction {
            let ids = [id] + subCollectionIDs(of: id)
            for doomed in ids {
                try db.run("DELETE FROM collection_items WHERE collection_id = ?", [.int(doomed)])
                try db.run("DELETE FROM collections WHERE id = ?", [.int(doomed)])
            }
        }
    }

    public func addToCollection(id: Int64, sampleIDs: [Int64], at date: Date = Date()) throws {
        try db.transaction {
            for sample in sampleIDs {
                try db.run("INSERT OR IGNORE INTO collection_items(collection_id, sample_id, added) VALUES(?, ?, ?)",
                           [.int(id), .int(sample), .double(date.timeIntervalSince1970)])
            }
        }
    }

    public func removeFromCollection(id: Int64, sampleIDs: [Int64]) throws {
        try db.transaction {
            for sample in sampleIDs {
                try db.run("DELETE FROM collection_items WHERE collection_id = ? AND sample_id = ?", [.int(id), .int(sample)])
            }
        }
    }

    /// Sample ids in the order they were added.
    public func collectionMembers(id: Int64) -> [Int64] {
        (try? db.query("SELECT sample_id FROM collection_items WHERE collection_id = ? ORDER BY added, rowid",
                       [.int(id)]) { $0.int(0) }) ?? []
    }
}

/// Copies files out of the library (for sharing a kit, or a project folder), leaving the originals alone.
public enum SampleExporter {
    public struct Report: Sendable {
        public var copied: [URL] = []
        public var failures: [(source: URL, message: String)] = []
    }

    /// Copies each file into `folder`, never overwriting: a clash becomes "name 2.wav", "name 3.wav", …
    public static func copy(_ sources: [URL], to folder: URL, fileManager fm: FileManager = .default) -> Report {
        copy(sources.map { (source: $0, fileName: $0.lastPathComponent) }, to: folder, fileManager: fm)
    }

    /// Like `copy(_:to:)`, with the name each file should get in the destination.
    public static func copy(_ items: [(source: URL, fileName: String)], to folder: URL, fileManager fm: FileManager = .default) -> Report {
        var report = Report()
        let sources = items.map(\.source)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            report.failures = sources.map { ($0, error.localizedDescription) }
            return report
        }
        for (source, fileName) in items {
            let target = uniqueURL(in: folder, fileName: fileName, fileManager: fm)
            do { try fm.copyItem(at: source, to: target); report.copied.append(target) }
            catch { report.failures.append((source, error.localizedDescription)) }
        }
        return report
    }

    /// `fileName` inside `folder`, or "name 2.wav", "name 3.wav", … when that name is taken.
    public static func uniqueURL(in folder: URL, fileName: String, fileManager fm: FileManager = .default) -> URL {
        let named = URL(fileURLWithPath: fileName)
        let stem = named.deletingPathExtension().lastPathComponent, ext = named.pathExtension
        var target = folder.appendingPathComponent(fileName)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return target
    }
}
