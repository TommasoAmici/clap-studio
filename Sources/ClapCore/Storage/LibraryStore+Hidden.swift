import Foundation

/// Hiding is reversible: a hidden sample stays in the index (and on disk), it is just left out of views.
extension LibraryStore {
    public func setHidden(_ ids: [Int64], _ hidden: Bool) throws {
        try db.transaction {
            for id in ids { try db.run("UPDATE samples SET hidden = ? WHERE id = ?", [.int(hidden ? 1 : 0), .int(id)]) }
        }
    }

    /// File fingerprints by sample id (absent when the file could not be read).
    public func fingerprints() -> [Int64: String] {
        let rows = (try? db.query("SELECT id, fingerprint FROM samples WHERE fingerprint IS NOT NULL") { ($0.int(0), $0.text(1)) }) ?? []
        return Dictionary(uniqueKeysWithValues: rows)
    }
}
