import Foundation

/// What files say about themselves (see `FileMetadata`), kept beside the library so it can be shown and searched.
extension LibraryStore {
    private static let separator = "\u{1F}"

    /// Replaces what is stored for the samples; an empty result clears the row.
    public func saveFileMetadata(_ items: [(id: Int64, meta: FileMetadata)]) throws {
        try db.transaction {
            for item in items {
                try db.run("DELETE FROM file_meta WHERE sample_id = ?", [.int(item.id)])
                guard !item.meta.isEmpty else { continue }
                let m = item.meta
                try db.run("""
                    INSERT INTO file_meta(sample_id, title, description, keywords, category, subcategory, ucs_id, creator, source, originator, date)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [.int(item.id), .text(m.title), .text(m.description), .text(m.keywords.joined(separator: Self.separator)),
                          .text(m.category), .text(m.subcategory), .text(m.ucsID), .text(m.creator), .text(m.source),
                          .text(m.originator), .text(m.date)])
            }
        }
    }

    public func fileMetadata(sampleID: Int64) -> FileMetadata? {
        let rows = (try? db.query("""
            SELECT title, description, keywords, category, subcategory, ucs_id, creator, source, originator, date
            FROM file_meta WHERE sample_id = ?
            """, [.int(sampleID)]) { row -> FileMetadata in
            var m = FileMetadata()
            m.title = row.text(0); m.description = row.text(1)
            m.keywords = row.text(2).components(separatedBy: Self.separator).filter { !$0.isEmpty }
            m.category = row.text(3); m.subcategory = row.text(4); m.ucsID = row.text(5)
            m.creator = row.text(6); m.source = row.text(7); m.originator = row.text(8); m.date = row.text(9)
            return m
        }) ?? []
        return rows.first
    }

    /// The keywords files carry, for turning them into tags.
    public func fileKeywords(sampleIDs: [Int64]) -> [Int64: [String]] {
        let wanted = Set(sampleIDs)
        let rows = (try? db.query("SELECT sample_id, keywords FROM file_meta WHERE keywords != ''") {
            ($0.int(0), $0.text(1).components(separatedBy: Self.separator).filter { !$0.isEmpty })
        }) ?? []
        return Dictionary(rows.filter { wanted.contains($0.0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Everything a sample's file says, lowercased and in one string, for searching as the user types.
    public func fileMetadataSearchText() -> [Int64: String] {
        let rows = (try? db.query("""
            SELECT sample_id, title || ' ' || description || ' ' || keywords || ' ' || category || ' ' || subcategory || ' '
                || ucs_id || ' ' || creator || ' ' || source || ' ' || originator FROM file_meta
            """) { ($0.int(0), $0.text(1).replacingOccurrences(of: Self.separator, with: " ").lowercased()) }) ?? []
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    /// Writes the sample's category and tags (and moods) into its WAV file, then makes the library agree with
    /// the changed file so it is not read again as new.
    @discardableResult
    public func writeTagsToFile(sample: SampleRecord, keepBackup: Bool) throws -> URL? {
        let backup = try WavMetadataWriter.write(category: sample.effectiveCategory, keywords: Self.keywords(of: sample),
                                                 to: sample.url, keepBackup: keepBackup)
        let attrs = try FileManager.default.attributesOfItem(atPath: sample.url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? sample.size
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? sample.mtime
        try updateFileAttributes(sampleID: sample.id, size: size, mtime: mtime, fingerprint: FileFingerprint.compute(url: sample.url))
        try saveFileMetadata([(sample.id, FileMetadataReader.read(url: sample.url))])
        return backup
    }

    /// What is written as keywords: the tags, then the moods.
    public static func keywords(of sample: SampleRecord) -> [String] {
        var seen = Set<String>()
        return (sample.tags + sample.moods).filter { seen.insert($0.lowercased()).inserted }
    }
}
