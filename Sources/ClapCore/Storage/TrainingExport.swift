import Foundation

public enum TrainingExportError: Error, CustomStringConvertible {
    case changedDuringExport
    case cannotCreateFolder(String)

    public var description: String {
        switch self {
        case .changedDuringExport: return "The library changed while exporting. Try again once indexing has finished."
        case .cannotCreateFolder(let m): return "Could not create the export folder: \(m)"
        }
    }
}

/// Writes the embeddings of categorised samples with their categories, to train a classifier outside the app.
///
/// The result is a folder with `embeddings.npy` (float32, rows x dimension, NumPy format 1.0), `labels.csv` (one row per
/// embedding, same order) and `metadata.json`. Read-only: the library is not changed.
public enum TrainingExport {
    public struct Summary: Sendable, Equatable {
        public var folder: URL
        public var rows = 0
        public var manual = 0
        public var automatic = 0
        /// No category: the classifier was not confident and nothing was set by hand.
        public var skippedUncategorised = 0
        /// Their file embedding averages unrelated sounds and their category is forced.
        public var skippedFieldRecordings = 0
        /// Automatic labels left out because only manual ones were asked for.
        public var skippedAutomatic = 0
    }

    public static let embeddingsFile = "embeddings.npy"
    public static let labelsFile = "labels.csv"
    public static let metadataFile = "metadata.json"
    static let chunkSize = 4096
    static let columns = ["row", "path", "relative_path", "name", "category", "source", "automatic_category",
                          "automatic_confidence", "fingerprint", "model_version"]

    /// Library samples (not temporary roots) embedded with the current model.
    private static let base = """
        FROM samples s JOIN roots r ON r.id = s.root_id
        WHERE s.status = 'ok' AND s.model_version = ? AND s.embedding IS NOT NULL AND r.transient = 0
        """
    private static let effective = "COALESCE(s.category_manual, s.category)"

    /// Exports into a new folder inside `parent` and returns what was written.
    public static func write(store: LibraryStore, into parent: URL, manualOnly: Bool = false,
                             date: Date = Date()) throws -> Summary {
        let folder = try makeFolder(in: parent, date: date)
        var summary = Summary(folder: folder)
        let model = SQLValue.text(ClapEmbedder.versionTag)
        let long = SQLValue.double(FieldRecording.minimumSeconds)
        func count(_ extra: String, _ params: [SQLValue] = []) throws -> Int {
            Int(try store.db.scalarInt("SELECT COUNT(*) \(base) \(extra)", [model] + params) ?? 0)
        }

        let eligible = "AND COALESCE(s.duration, 0) < ? AND \(effective) IS NOT NULL"
            + (manualOnly ? " AND s.category_manual IS NOT NULL" : "")
        summary.rows = try count(eligible, [long])
        summary.manual = try count(eligible + " AND s.category_manual IS NOT NULL", [long])
        summary.automatic = summary.rows - summary.manual
        summary.skippedFieldRecordings = try count("AND COALESCE(s.duration, 0) >= ?", [long])
        summary.skippedUncategorised = try count("AND COALESCE(s.duration, 0) < ? AND \(effective) IS NULL", [long])
        if manualOnly {
            summary.skippedAutomatic = try count("""
                AND COALESCE(s.duration, 0) < ? AND s.category_manual IS NULL AND s.category IS NOT NULL
                """, [long])
        }

        let dimension = try store.db.scalarInt("SELECT length(s.embedding) / 2 \(base) \(eligible) LIMIT 1", [model, long])
            .map(Int.init) ?? 512
        let fm = FileManager.default
        let npyURL = folder.appendingPathComponent(embeddingsFile), csvURL = folder.appendingPathComponent(labelsFile)
        guard fm.createFile(atPath: npyURL.path, contents: nil), fm.createFile(atPath: csvURL.path, contents: nil) else {
            throw TrainingExportError.cannotCreateFolder("cannot create files in \(folder.path)")
        }
        let npy = try FileHandle(forWritingTo: npyURL), csv = try FileHandle(forWritingTo: csvURL)
        defer { try? npy.close(); try? csv.close() }
        npy.write(npyHeader(rows: summary.rows, columns: dimension))
        csv.write(Data((csvLine(columns) + "\n").utf8))

        var written = 0
        var lastID: Int64 = 0
        while true {
            let rows = try store.db.query("""
                SELECT s.id, r.path, s.rel_path, s.name, \(effective), s.category_manual IS NOT NULL, s.category,
                       s.category_conf, s.fingerprint, s.model_version, s.embedding
                \(base) \(eligible) AND s.id > ? ORDER BY s.id LIMIT ?
                """, [model, long, .int(lastID), .int(Int64(chunkSize))]) { row in
                (id: row.int(0), embedding: row.blob(10), fields: [
                    row.text(1) + "/" + row.text(2), row.text(2), row.text(3), row.text(4),
                    row.int(5) != 0 ? "manual" : "automatic",
                    row.isNull(6) ? "" : row.text(6),
                    row.isNull(7) ? "" : String(format: "%.4f", row.double(7)),
                    row.isNull(8) ? "" : row.text(8), row.text(9)])
            }
            guard let last = rows.last else { break }
            var floats = Data()
            var lines = ""
            for (i, row) in rows.enumerated() {
                let vector = VectorCodec.decodeFloat16(row.embedding)
                guard vector.count == dimension else { throw TrainingExportError.changedDuringExport }
                floats.append(VectorCodec.encodeFloat32(vector))
                lines += csvLine([String(written + i)] + row.fields) + "\n"
            }
            npy.write(floats)
            csv.write(Data(lines.utf8))
            written += rows.count
            lastID = last.id
        }
        guard written == summary.rows else { throw TrainingExportError.changedDuringExport }

        try metadata(summary, dimension: dimension, manualOnly: manualOnly, date: date)
            .write(to: folder.appendingPathComponent(metadataFile))
        return summary
    }

    // MARK: files

    static func makeFolder(in parent: URL, date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "clap-training-export-" + formatter.string(from: date)
        let fm = FileManager.default
        var candidate = parent.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name)-\(n)")
            n += 1
        }
        do { try fm.createDirectory(at: candidate, withIntermediateDirectories: false) } catch {
            throw TrainingExportError.cannotCreateFolder(error.localizedDescription)
        }
        return candidate
    }

    /// NumPy format 1.0 header for a C-ordered little-endian float32 matrix; its length is a multiple of 64.
    static func npyHeader(rows: Int, columns: Int) -> Data {
        var dict = "{'descr': '<f4', 'fortran_order': False, 'shape': (\(rows), \(columns)), }"
        let unpadded = 10 + dict.utf8.count + 1
        dict += String(repeating: " ", count: (64 - unpadded % 64) % 64) + "\n"
        var data = Data([0x93]) + Data("NUMPY".utf8) + Data([1, 0])
        let length = UInt16(dict.utf8.count)
        data.append(UInt8(length & 0xFF)); data.append(UInt8(length >> 8))
        data.append(Data(dict.utf8))
        return data
    }

    /// RFC 4180: fields with a comma, quote or line break are quoted, quotes doubled.
    static func csvLine(_ fields: [String]) -> String {
        fields.map { field in
            guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",")
    }

    private static func metadata(_ s: Summary, dimension: Int, manualOnly: Bool, date: Date) throws -> Data {
        let info: [String: Any] = [
            "model_version": ClapEmbedder.versionTag,
            "category_tag": LibraryStore.categoryTag,
            "embedding_dimension": dimension,
            "rows": s.rows, "manual_rows": s.manual, "automatic_rows": s.automatic,
            "manual_labels_only": manualOnly,
            "skipped_uncategorised": s.skippedUncategorised,
            "skipped_field_recordings": s.skippedFieldRecordings,
            "skipped_automatic": s.skippedAutomatic,
            "exported_at": ISO8601DateFormatter().string(from: date),
            "categories": SoundCategories.names,
            "files": [embeddingsFile: "float32 little-endian, rows x embedding_dimension, numpy.load",
                      labelsFile: "one row per embedding, same order"],
        ]
        return try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
    }
}
