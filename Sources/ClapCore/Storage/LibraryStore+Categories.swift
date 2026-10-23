import Foundation

/// Persistence of sound categories (automatic, with the user's corrections kept separately).
extension LibraryStore {
    /// Embedded samples whose automatic category is missing or was computed with other phrases/models.
    public func categoryBacklog() -> Int {
        Int((try? db.scalarInt("""
            SELECT COUNT(*) FROM samples WHERE status = 'ok' AND embedding IS NOT NULL AND model_version = ?
              AND (category_version IS NULL OR category_version != ?)
            """, [.text(ClapEmbedder.versionTag), .text(Self.categoryTag)])) ?? 0)
    }

    static var categoryTag: String { "\(ClapEmbedder.versionTag)/\(SoundCategories.version)" }

    /// Classifies every sample that needs it. Cheap (one matrix product per chunk), so it is not cancellable.
    @discardableResult
    public func categorize(with categorizer: Categorizer) throws -> Int {
        var pending: [(id: Int64, result: Categorizer.Result)] = []
        let long = Set(try db.query("SELECT id FROM samples WHERE \(FieldRecording.sqlIs())") { $0.int(0) })
        try forEachEmbeddingChunk(modelVersion: ClapEmbedder.versionTag) { ids, flat, count in
            let results = categorizer.classify(flat: flat, count: count)
            // Field recordings follow the length rule and the user's choice.
            pending += zip(ids, results).map { id, result in
                (id: id, result: long.contains(id) ? Categorizer.Result(category: SoundCategories.fieldRecording, confidence: 1) : result)
            }
        }
        try db.transaction {
            for item in pending {
                try db.run("""
                    UPDATE samples SET category = ?, category_conf = ?, category_version = ?
                    WHERE id = ? AND (category_version IS NULL OR category_version != ?)
                    """, [item.result.category.map { .text($0) } ?? .null, .double(Double(item.result.confidence)),
                          .text(Self.categoryTag), .int(item.id), .text(Self.categoryTag)])
            }
        }
        return pending.count
    }

    /// Several samples at once, each with its own value (nil goes back to the automatic category).
    public func setManualCategories(_ values: [(id: Int64, category: String?)]) throws {
        try db.transaction {
            for value in values {
                try db.run("UPDATE samples SET category_manual = ? WHERE id = ?",
                           [value.category.map { .text($0) } ?? .null, .int(value.id)])
            }
        }
    }

    /// The user's own category (pass nil to go back to the automatic one).
    public func setManualCategory(sampleID: Int64, _ category: String?) throws {
        try db.run("UPDATE samples SET category_manual = ? WHERE id = ?",
                   [category.map { .text($0) } ?? .null, .int(sampleID)])
    }
}
