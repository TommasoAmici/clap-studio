import Foundation

/// Free-text tags the user attaches to samples (stored in the index only).
extension LibraryStore {
    /// Cleans a typed tag: trimmed, no commas or control characters, at most 40 characters.
    public static func cleanTag(_ raw: String) -> String {
        let allowed = raw.unicodeScalars.filter { $0 != "," && !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(allowed)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(40).description
    }

    public func addTag(_ tag: String, to ids: [Int64]) throws {
        let clean = Self.cleanTag(tag)
        guard !clean.isEmpty else { return }
        try db.transaction {
            for id in ids { try db.run("INSERT OR IGNORE INTO sample_tags(sample_id, tag) VALUES(?, ?)", [.int(id), .text(clean)]) }
        }
    }

    public func removeTag(_ tag: String, from ids: [Int64]) throws {
        try db.transaction {
            for id in ids { try db.run("DELETE FROM sample_tags WHERE sample_id = ? AND tag = ?", [.int(id), .text(tag)]) }
        }
    }
}
