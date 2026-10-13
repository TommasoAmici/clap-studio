import CryptoKit
import Foundation

public enum CueWriteError: Error, CustomStringConvertible {
    case unsupported(String)
    case malformed
    case verificationFailed
    public var description: String {
        switch self {
        case .unsupported(let m): return "Cannot write cues: \(m)"
        case .malformed: return "The WAV file is malformed or truncated"
        case .verificationFailed: return "Verification failed; the original file was not changed"
        }
    }
}

/// Explicit "write cues to file" action (WAV only). Rewrites only the `cue ` chunk and the
/// `LIST/adtl` labels, copying every other chunk byte for byte, then atomically replaces
/// the original after verifying that audio data and cues read back identically.
public enum WavCueWriter {
    @discardableResult
    public static func write(cues: [FileCue], to url: URL, keepBackup: Bool) throws -> URL? {
        let ext = url.pathExtension.lowercased()
        guard ext == "wav" || ext == "wave" else { throw CueWriteError.unsupported("only WAV files are supported") }
        let original = try Data(contentsOf: url, options: .alwaysMapped)
        guard original.count >= 12,
              String(decoding: original[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: original[8..<12], as: UTF8.self) == "WAVE" else {
            throw CueWriteError.unsupported("not a RIFF/WAVE file")
        }
        let chunks = WavChunks.parse(original)
        guard let last = chunks.last, last.end >= original.count - 1, chunks.contains(where: { $0.id == "data" }) else {
            throw CueWriteError.malformed
        }

        let sorted = cues.sorted { $0.frame < $1.frame }
        var body = Data("WAVE".utf8)
        for chunk in chunks where !isCueRelated(chunk, in: original) {
            body.append(original[chunk.headerStart..<min(chunk.end, original.count)])
            if chunk.size & 1 == 1 && chunk.end > original.count { body.append(0) }
        }
        if !sorted.isEmpty {
            body.append(cueChunk(sorted))
            if sorted.contains(where: { !$0.label.isEmpty }) { body.append(adtlChunk(sorted)) }
        }
        guard body.count + 4 < Int(UInt32.max) else { throw CueWriteError.unsupported("file too large for RIFF") }
        var output = Data("RIFF".utf8)
        output.appendLE32(UInt32(body.count))
        output.append(body)

        let temp = url.deletingLastPathComponent().appendingPathComponent(".clap-\(UUID().uuidString).tmp")
        do {
            try output.write(to: temp)
            try verify(temp, expectedCues: sorted, original: original)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let perms = attrs[.posixPermissions] { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: temp.path) }
            var backupURL: URL?
            if keepBackup { backupURL = try makeBackup(of: url) }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            return backupURL
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    private static func isCueRelated(_ chunk: WavChunk, in data: Data) -> Bool {
        if chunk.id == "cue " { return true }
        return chunk.id == "LIST" && chunk.size >= 4
            && String(decoding: data[chunk.dataStart..<(chunk.dataStart + 4)], as: UTF8.self) == "adtl"
    }

    private static func cueChunk(_ cues: [FileCue]) -> Data {
        var d = Data("cue ".utf8)
        d.appendLE32(UInt32(4 + 24 * cues.count))
        d.appendLE32(UInt32(cues.count))
        for (i, cue) in cues.enumerated() {
            d.appendLE32(UInt32(i + 1))
            d.appendLE32(UInt32(truncatingIfNeeded: cue.frame))
            d.append(contentsOf: Array("data".utf8))
            d.appendLE32(0); d.appendLE32(0)
            d.appendLE32(UInt32(truncatingIfNeeded: cue.frame))
        }
        return d
    }

    private static func adtlChunk(_ cues: [FileCue]) -> Data {
        var inner = Data("adtl".utf8)
        for (i, cue) in cues.enumerated() where !cue.label.isEmpty {
            var text = Data(cue.label.utf8); text.append(0)
            inner.append(contentsOf: Array("labl".utf8))
            inner.appendLE32(UInt32(4 + text.count))
            inner.appendLE32(UInt32(i + 1))
            inner.append(text)
            if text.count & 1 == 1 { inner.append(0) }
        }
        var d = Data("LIST".utf8)
        d.appendLE32(UInt32(inner.count))
        d.append(inner)
        return d
    }

    private static func verify(_ temp: URL, expectedCues: [FileCue], original: Data) throws {
        let written = try Data(contentsOf: temp, options: .alwaysMapped)
        guard CueFileReader.readWav(written) == expectedCues,
              audioDigest(written) == audioDigest(original),
              WavChunks.parse(written).first(where: { $0.id == "fmt " }).map({ written[$0.dataStart..<($0.dataStart + $0.size)] })
                == WavChunks.parse(original).first(where: { $0.id == "fmt " }).map({ original[$0.dataStart..<($0.dataStart + $0.size)] })
        else { throw CueWriteError.verificationFailed }
    }

    private static func audioDigest(_ data: Data) -> String? {
        guard let chunk = WavChunks.parse(data).first(where: { $0.id == "data" }) else { return nil }
        return SHA256.hash(data: data[chunk.dataStart..<(chunk.dataStart + chunk.size)]).map { String(format: "%02x", $0) }.joined()
    }

    static func makeBackup(of url: URL) throws -> URL {
        var candidate = url.appendingPathExtension("bak")
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            n += 1
            candidate = url.appendingPathExtension("bak\(n)")
        }
        try FileManager.default.copyItem(at: url, to: candidate)
        return candidate
    }
}

extension Data {
    mutating func appendLE32(_ v: UInt32) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)])
    }
}
