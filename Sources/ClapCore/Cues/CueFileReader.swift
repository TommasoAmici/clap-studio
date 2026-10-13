import Foundation

public struct FileCue: Equatable, Hashable, Sendable {
    public var frame: Int64
    public var label: String
    public init(frame: Int64, label: String = "") { self.frame = frame; self.label = label }
}

/// Reads embedded cue points from WAV (`cue ` + `LIST/adtl`) and AIFF (`MARK`) headers
/// without decoding audio. Every chunk size is validated against the file length so
/// malformed or hostile files cannot cause out-of-bounds reads.
public enum CueFileReader {
    public static func read(url: URL) -> [FileCue] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count >= 12 else { return [] }
        switch String(decoding: data[0..<4], as: UTF8.self) {
        case "RIFF": return readWav(data)
        case "FORM": return readAiff(data)
        default: return []
        }
    }

    // MARK: WAV

    static func readWav(_ data: Data) -> [FileCue] {
        guard String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else { return [] }
        var points: [(id: UInt32, frame: UInt32)] = []
        var labels: [UInt32: String] = [:]
        for chunk in WavChunks.parse(data) {
            switch chunk.id {
            case "cue ":
                guard chunk.size >= 4 else { continue }
                let count = Int(data.le32(chunk.dataStart))
                for i in 0..<count {
                    let o = chunk.dataStart + 4 + i * 24
                    guard o + 24 <= chunk.dataStart + chunk.size else { break }
                    points.append((data.le32(o), data.le32(o + 20)))   // id, sampleOffset
                }
            case "LIST":
                guard chunk.size >= 4, String(decoding: data[chunk.dataStart..<(chunk.dataStart + 4)], as: UTF8.self) == "adtl" else { continue }
                var o = chunk.dataStart + 4
                let end = chunk.dataStart + chunk.size
                while o + 8 <= end {
                    let sid = String(decoding: data[o..<(o + 4)], as: UTF8.self)
                    let size = Int(data.le32(o + 4))
                    guard o + 8 + size <= end else { break }
                    if (sid == "labl" || sid == "note"), size >= 4 {
                        let text = data[(o + 12)..<(o + 8 + size)].prefix { $0 != 0 }
                        if labels[data.le32(o + 8)] == nil || sid == "labl" {
                            labels[data.le32(o + 8)] = String(decoding: text, as: UTF8.self)
                        }
                    }
                    o += 8 + size + (size & 1)
                }
            default: break
            }
        }
        return points.map { FileCue(frame: Int64($0.frame), label: labels[$0.id] ?? "") }
            .sorted { $0.frame < $1.frame }
    }

    // MARK: AIFF

    static func readAiff(_ data: Data) -> [FileCue] {
        let form = String(decoding: data[8..<12], as: UTF8.self)
        guard form == "AIFF" || form == "AIFC" else { return [] }
        var o = 12
        while o + 8 <= data.count {
            let id = String(decoding: data[o..<(o + 4)], as: UTF8.self)
            let size = Int(data.be32(o + 4))
            let start = o + 8
            guard size >= 0, start + size <= data.count else { break }
            if id == "MARK", size >= 2 {
                var cues: [FileCue] = []
                let count = Int(data.be16(start))
                var p = start + 2
                for _ in 0..<count {
                    guard p + 7 <= start + size else { break }
                    let frame = Int64(data.be32(p + 2))
                    let nameLen = Int(data[p + 6])
                    guard p + 7 + nameLen <= start + size else { break }
                    let name = String(decoding: data[(p + 7)..<(p + 7 + nameLen)], as: UTF8.self)
                    cues.append(FileCue(frame: frame, label: name))
                    p += 7 + nameLen + ((nameLen + 1) & 1)   // pstring padded to even length
                }
                return cues.sorted { $0.frame < $1.frame }
            }
            o = start + size + (size & 1)
        }
        return []
    }
}

/// RIFF chunk layout of a WAV file (offsets are absolute).
struct WavChunk {
    let id: String
    let headerStart: Int
    let dataStart: Int
    let size: Int
    var end: Int { dataStart + size + (size & 1) }
}

enum WavChunks {
    static func isRiffWave(_ data: Data) -> Bool {
        data.count >= 12 && String(decoding: data[0..<4], as: UTF8.self) == "RIFF" && String(decoding: data[8..<12], as: UTF8.self) == "WAVE"
    }

    /// The file mapped into memory, when it is a WAV file.
    static func mappedWav(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), isRiffWave(data) else { return nil }
        return data
    }

    static func isList(_ chunk: WavChunk, ofType type: String, in data: Data) -> Bool {
        chunk.id == "LIST" && chunk.size >= 4 && String(decoding: data[chunk.dataStart..<(chunk.dataStart + 4)], as: UTF8.self) == type
    }

    /// The entries of an INFO list, in order, with their text read up to the first zero byte.
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

    /// Text up to the first zero byte, trimmed.
    static func text(_ bytes: Data) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stops at the first chunk that does not fit inside the file.
    static func parse(_ data: Data) -> [WavChunk] {
        var chunks: [WavChunk] = []
        var o = 12
        while o + 8 <= data.count {
            let id = String(decoding: data[o..<(o + 4)], as: UTF8.self)
            let size = Int(data.le32(o + 4))
            let start = o + 8
            guard start + size <= data.count else { break }
            chunks.append(WavChunk(id: id, headerStart: o, dataStart: start, size: size))
            o = start + size + (size & 1)
        }
        return chunks
    }
}

extension Data {
    func le32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= count else { return 0 }
        let i = startIndex + o
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
    func be32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= count else { return 0 }
        let i = startIndex + o
        return UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
    }
    func be16(_ o: Int) -> UInt16 {
        guard o >= 0, o + 2 <= count else { return 0 }
        let i = startIndex + o
        return UInt16(self[i]) << 8 | UInt16(self[i + 1])
    }
}
