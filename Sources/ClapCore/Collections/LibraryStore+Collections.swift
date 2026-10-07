import Foundation

public struct CollectionRecord: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String
    public var count: Int
}

/// Favorites and named collections. Both live in the index only; the files are never touched.
extension LibraryStore {
    public func setFavorite(_ ids: [Int64], _ favorite: Bool) throws {
        try db.transaction {
            for id in ids { try db.run("UPDATE samples SET favorite = ? WHERE id = ?", [.int(favorite ? 1 : 0), .int(id)]) }
        }
    }

    public func collections() -> [CollectionRecord] {
        (try? db.query("""
            SELECT c.id, c.name, COUNT(i.sample_id) FROM collections c
            LEFT JOIN collection_items i ON i.collection_id = c.id
            GROUP BY c.id ORDER BY c.name COLLATE NOCASE
            """) { CollectionRecord(id: $0.int(0), name: $0.text(1), count: Int($0.int(2))) }) ?? []
    }

    @discardableResult
    public func createCollection(name: String, at date: Date = Date()) throws -> CollectionRecord {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.run("INSERT INTO collections(name, created) VALUES(?, ?)",
                   [.text(clean.isEmpty ? "Untitled" : clean), .double(date.timeIntervalSince1970)])
        let id = try db.scalarInt("SELECT MAX(id) FROM collections") ?? 0
        return CollectionRecord(id: id, name: clean.isEmpty ? "Untitled" : clean, count: 0)
    }

    public func renameCollection(id: Int64, to name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        try db.run("UPDATE collections SET name = ? WHERE id = ?", [.text(clean), .int(id)])
    }

    public func deleteCollection(id: Int64) throws {
        try db.transaction {
            try db.run("DELETE FROM collection_items WHERE collection_id = ?", [.int(id)])
            try db.run("DELETE FROM collections WHERE id = ?", [.int(id)])
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
        var report = Report()
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            report.failures = sources.map { ($0, error.localizedDescription) }
            return report
        }
        for source in sources {
            let stem = source.deletingPathExtension().lastPathComponent, ext = source.pathExtension
            var target = folder.appendingPathComponent(source.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
                n += 1
            }
            do { try fm.copyItem(at: source, to: target); report.copied.append(target) }
            catch { report.failures.append((source, error.localizedDescription)) }
        }
        return report
    }
}
