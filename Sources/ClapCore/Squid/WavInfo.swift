import Foundation

/// The category of a sample, kept inside the WAV file itself as a standard `LIST`/`INFO` genre entry (`IGNR`).
/// The tag travels with the file, so a stick shows a sample under the category it had when it was sent, and
/// other software reads it as the file's genre. The chunk goes after the audio, so nothing that reads the
/// header or the audio sees a different file.
public enum WavInfo {
    static let genreID = "IGNR"

    /// Adds a genre entry to a finished WAV file. The file is changed in place: only the new chunk at the end
    /// and the RIFF length at the start are written.
    public static func appendGenre(_ genre: String, to url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count >= 12, String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else { throw CueWriteError.unsupported("not a RIFF/WAVE file") }
        let chunks = WavChunks.parse(data)
        // Only a file whose chunks run to its very end can take another one.
        guard let last = chunks.last, last.end >= data.count - 1, last.end <= data.count + 1,
              chunks.contains(where: { $0.id == "data" }) else { throw CueWriteError.malformed }

        var text = Data(genre.utf8)
        text.append(0)
        var info = Data("INFO".utf8)
        info.append(contentsOf: Array(genreID.utf8))
        info.appendLE32(UInt32(text.count))
        info.append(text)
        if text.count & 1 == 1 { info.append(0) }
        var chunk = Data("LIST".utf8)
        chunk.appendLE32(UInt32(info.count))
        chunk.append(info)

        var tail = Data()
        if last.end > data.count { tail.append(0) }        // the previous chunk's own padding byte
        tail.append(chunk)
        let total = data.count + tail.count - 8
        guard total < Int(UInt32.max) else { throw CueWriteError.unsupported("file too large for RIFF") }

        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: tail)
        try handle.seek(toOffset: 4)
        var size = Data()
        size.appendLE32(UInt32(total))
        try handle.write(contentsOf: size)
    }

    /// The genre entry of a WAV file, if it has one.
    public static func genre(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count >= 12,
              String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        for chunk in WavChunks.parse(data) where chunk.id == "LIST" && chunk.size >= 4
            && String(decoding: data[chunk.dataStart..<(chunk.dataStart + 4)], as: UTF8.self) == "INFO" {
            var o = chunk.dataStart + 4
            let end = chunk.dataStart + chunk.size
            while o + 8 <= end {
                let id = String(decoding: data[o..<(o + 4)], as: UTF8.self)
                let size = Int(data.le32(o + 4))
                guard o + 8 + size <= end else { break }
                if id == genreID {
                    let text = String(decoding: data[(o + 8)..<(o + 8 + size)].prefix { $0 != 0 }, as: UTF8.self)
                    return text.isEmpty ? nil : text
                }
                o += 8 + size + (size & 1)
            }
        }
        return nil
    }

    /// The sample's category as stored by `appendGenre`, spelled the way the app spells it. Anything that is not
    /// one of the app's categories is some other genre and is ignored, as is Field recording: that category
    /// makes the app cut a file into segments, which a sample for the module (11 seconds at most) never needs.
    public static func category(of url: URL) -> String? {
        guard let genre = genre(of: url)?.trimmingCharacters(in: .whitespaces) else { return nil }
        return SoundCategories.names.first { $0.caseInsensitiveCompare(genre) == .orderedSame && $0 != SoundCategories.fieldRecording }
    }
}
