import Foundation

/// Reads descriptive metadata from a file: iXML first (what library tools and recorders write), then
/// `LIST`/`INFO`, then the Broadcast Wave `bext` chunk, and last the UCS name of the file.
public enum FileMetadataReader {
    public static func read(url: URL) -> FileMetadata {
        var meta = FileMetadata()
        let ext = url.pathExtension.lowercased()
        if ext == "wav" || ext == "wave" || ext == "bwf",
           let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count >= 12,
           String(decoding: data[0..<4], as: UTF8.self) == "RIFF", String(decoding: data[8..<12], as: UTF8.self) == "WAVE" {
            meta = readWav(data)
        }
        if let ucs = UCSName.parse(fileName: url.lastPathComponent) { meta.fill(from: ucs) }
        return meta
    }

    static func readWav(_ data: Data) -> FileMetadata {
        var ixml = FileMetadata(), info = FileMetadata(), bext = FileMetadata()
        for chunk in WavChunks.parse(data) {
            switch chunk.id {
            case "iXML":
                ixml.fill(from: fromMarkup(String(decoding: data[chunk.dataStart..<(chunk.dataStart + chunk.size)], as: UTF8.self)))
            case "bext": bext.fill(from: fromBext(data, chunk))
            case "LIST":
                guard chunk.size >= 4, String(decoding: data[chunk.dataStart..<(chunk.dataStart + 4)], as: UTF8.self) == "INFO" else { continue }
                info.fill(from: fromInfo(data, chunk))
            default: break
            }
        }
        var meta = ixml
        meta.fill(from: info)
        meta.fill(from: bext)
        return meta
    }

    // MARK: LIST / INFO

    /// The entries of every INFO list in the file, in order.
    static func infoEntries(_ data: Data, _ chunk: WavChunk) -> [(id: String, text: String)] {
        var entries: [(String, String)] = []
        var o = chunk.dataStart + 4
        let end = chunk.dataStart + chunk.size
        while o + 8 <= end {
            let id = String(decoding: data[o..<(o + 4)], as: UTF8.self)
            let size = Int(data.le32(o + 4))
            guard o + 8 + size <= end else { break }
            entries.append((id, text(data[(o + 8)..<(o + 8 + size)])))
            o += 8 + size + (size & 1)
        }
        return entries
    }

    private static func fromInfo(_ data: Data, _ chunk: WavChunk) -> FileMetadata {
        var meta = FileMetadata()
        for (id, value) in infoEntries(data, chunk) where !value.isEmpty {
            switch id {
            case "INAM": meta.title = value
            case "ICMT": if GeoParse.iso6709(value) == nil { meta.description = value }   // a place is not a description
            case "IKEY": meta.keywords = FileMetadata.splitKeywords(value)
            case "IGNR": meta.category = value
            case "IART": meta.creator = value
            case "IPRD": meta.source = value
            case "ISFT": meta.originator = value
            case "ICRD": meta.date = value
            default: break
            }
        }
        return meta
    }

    // MARK: bext

    /// Description (256 bytes), originator (32), originator reference (32) and origination date (10).
    private static func fromBext(_ data: Data, _ chunk: WavChunk) -> FileMetadata {
        var meta = FileMetadata()
        func field(_ from: Int, _ length: Int) -> String {
            guard chunk.size >= from + length else { return "" }
            return text(data[(chunk.dataStart + from)..<(chunk.dataStart + from + length)])
        }
        meta.description = field(0, 256)
        meta.originator = field(256, 32)
        meta.date = field(320, 10)
        return meta
    }

    // MARK: iXML

    private static func fromMarkup(_ markup: String) -> FileMetadata {
        var meta = FileMetadata()
        for m in Rx.matches(#"<([A-Za-z0-9_:.\-]+)(?:\s[^>]*)?>\s*([^<>]{1,4000}?)\s*</\1>"#, in: markup) {
            let name = m[1].lowercased().split(whereSeparator: { ":.".contains($0) }).last.map(String.init) ?? ""
            let value = unescape(m[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            func set(_ keyPath: WritableKeyPath<FileMetadata, String>) { if meta[keyPath: keyPath].isEmpty { meta[keyPath: keyPath] = value } }
            switch name {
            case "fxname", "title", "user_title": set(\.title)
            case "user_description", "description", "notes", "note", "user_comment": set(\.description)
            case "user_keywords", "keywords", "keyword":
                if meta.keywords.isEmpty { meta.keywords = FileMetadata.splitKeywords(value) }
            case "category", "user_category", "usercategory": set(\.category)
            case "subcategory", "user_subcategory": set(\.subcategory)
            case "catid": set(\.ucsID)
            case "creatorid", "user_designer", "designer": set(\.creator)
            case "sourceid", "library", "user_library": set(\.source)
            default: break
            }
        }
        return meta
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Text up to the first zero byte, trimmed.
    private static func text(_ bytes: Data) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
