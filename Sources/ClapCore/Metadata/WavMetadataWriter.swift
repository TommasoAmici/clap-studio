import Foundation

/// Writes a sample's category and keywords into a WAV file as standard `LIST`/`INFO` entries (`IGNR` genre and
/// `IKEY` keywords), so other software and a re-imported library see them. Everything else in the INFO list is kept.
///
/// The audio is never rewritten and large files are not read into memory: the file is cloned, only the end of the
/// clone changes (an INFO list that already ends the file is cut off and written again, one in the middle is turned
/// into a `JUNK` chunk that readers skip), the result is checked, and only then does it replace the original.
public enum WavMetadataWriter {
    static let genreID = WavInfo.genreID, keywordsID = "IKEY"

    /// - Parameters:
    ///   - category: the genre to write; nil or empty removes the entry.
    ///   - keywords: written separated by `; `; none removes the entry.
    /// - Returns: the backup that was made, if `keepBackup`.
    @discardableResult
    public static func write(category: String?, keywords: [String], to url: URL, keepBackup: Bool) throws -> URL? {
        let ext = url.pathExtension.lowercased()
        guard ext == "wav" || ext == "wave" else { throw CueWriteError.unsupported("only WAV files can carry tags") }
        let original = try Data(contentsOf: url, options: .alwaysMapped)
        guard WavChunks.isRiffWave(original) else { throw CueWriteError.unsupported("not a RIFF/WAVE file") }
        let chunks = WavChunks.parse(original)
        guard let last = chunks.last, last.end >= original.count - 1, last.end <= original.count + 1,
              let dataChunk = chunks.first(where: { $0.id == "data" }) else { throw CueWriteError.malformed }

        func isInfo(_ chunk: WavChunk) -> Bool { WavChunks.isList(chunk, ofType: "INFO", in: original) }
        // Existing entries other than the two we set, in their order.
        var entries: [(id: String, text: String)] = []
        for chunk in chunks where isInfo(chunk) {
            entries += WavChunks.infoEntries(original, chunk).filter { $0.id != genreID && $0.id != keywordsID }
        }
        let genre = category?.trimmingCharacters(in: .whitespaces) ?? ""
        if !genre.isEmpty { entries.append((genreID, genre)) }
        if !keywords.isEmpty { entries.append((keywordsID, keywords.joined(separator: "; "))) }

        // INFO lists that end the file are replaced; any others stop being read as chunks.
        var cut = original.count
        var trailing = chunks
        while let tail = trailing.last, isInfo(tail) { cut = tail.headerStart; trailing.removeLast() }
        let junk = trailing.filter(isInfo).map(\.headerStart)
        let keptEnd = trailing.last?.end ?? cut

        var tail = Data()
        if keptEnd > cut { tail.append(0) }                                // the padding byte the last chunk was missing
        if !entries.isEmpty { tail.append(infoChunk(entries)) }
        let newLength = cut + tail.count
        guard newLength - 8 < Int(UInt32.max) else { throw CueWriteError.unsupported("file too large for RIFF") }

        let temp = url.deletingLastPathComponent().appendingPathComponent(".clap-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.copyItem(at: url, to: temp)
            let handle = try FileHandle(forUpdating: temp)
            do {
                for offset in junk { try handle.seek(toOffset: UInt64(offset)); try handle.write(contentsOf: Data("JUNK".utf8)) }
                try handle.truncate(atOffset: UInt64(cut))
                try handle.seek(toOffset: UInt64(cut))
                try handle.write(contentsOf: tail)
                try handle.seek(toOffset: 4)
                var size = Data()
                size.appendLE32(UInt32(newLength - 8))
                try handle.write(contentsOf: size)
                try handle.close()
            } catch { try? handle.close(); throw error }

            try verify(temp, original: original, dataChunk: dataChunk, category: genre, keywords: keywords)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let perms = attrs[.posixPermissions] { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: temp.path) }
            var backupURL: URL?
            if keepBackup { backupURL = try WavCueWriter.makeBackup(of: url) }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            return backupURL
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    static func infoChunk(_ entries: [(id: String, text: String)]) -> Data {
        var inner = Data("INFO".utf8)
        for entry in entries {
            var text = Data(entry.text.utf8)
            text.append(0)
            inner.append(contentsOf: Array(entry.id.utf8.prefix(4)))
            inner.appendLE32(UInt32(text.count))
            inner.append(text)
            if text.count & 1 == 1 { inner.append(0) }
        }
        var chunk = Data("LIST".utf8)
        chunk.appendLE32(UInt32(inner.count))
        chunk.append(inner)
        return chunk
    }

    /// The clone must still be a WAV file whose format and audio are where they were, and say what was asked.
    private static func verify(_ temp: URL, original: Data, dataChunk: WavChunk, category: String, keywords: [String]) throws {
        let written = try Data(contentsOf: temp, options: .alwaysMapped)
        let chunks = WavChunks.parse(written)
        guard written.count >= 12, Int(written.le32(4)) == written.count - 8,
              let data = chunks.first(where: { $0.id == "data" }), data.headerStart == dataChunk.headerStart, data.size == dataChunk.size,
              let fmt = chunks.first(where: { $0.id == "fmt " }), let oldFmt = WavChunks.parse(original).first(where: { $0.id == "fmt " }),
              written[fmt.dataStart..<(fmt.dataStart + fmt.size)] == original[oldFmt.dataStart..<(oldFmt.dataStart + oldFmt.size)],
              written[data.dataStart..<(data.dataStart + min(data.size, 4096))] == original[data.dataStart..<(data.dataStart + min(data.size, 4096))],
              chunks.last.map({ $0.end >= written.count - 1 }) == true
        else { throw CueWriteError.verificationFailed }
        var genre = "", words = ""
        for chunk in chunks where WavChunks.isList(chunk, ofType: "INFO", in: written) {
            for entry in WavChunks.infoEntries(written, chunk) {
                if entry.id == genreID { genre = entry.text } else if entry.id == keywordsID { words = entry.text }
            }
        }
        guard genre == category, FileMetadata.splitKeywords(words) == FileMetadata.splitKeywords(keywords.joined(separator: "; ")) else {
            throw CueWriteError.verificationFailed
        }
    }
}
