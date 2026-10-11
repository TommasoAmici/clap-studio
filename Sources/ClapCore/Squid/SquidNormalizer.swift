import Foundation

/// What matching the levels of everything on a stick did.
public struct SquidNormalizeReport: Equatable, Sendable {
    /// Files whose level was changed.
    public var adjusted = 0
    /// Files that were already at the common loudness (or silent).
    public var alreadyMatched = 0
    /// Files that are not 16-bit PCM WAV, which are left as they are.
    public var skipped: [String] = []
    public var failed: [String] = []
    public init() {}
}

/// Brings every WAV on a stick to the common loudness (see `LoudnessMatch`), in place. Only the samples inside the
/// `data` chunk change: the header, the category tag and every other chunk are written back byte for byte, and a
/// file is replaced only after the new copy is complete.
public enum SquidNormalizer {
    /// Differences under this are not worth rewriting a file for.
    static let toleranceDB: Float = 0.25

    public enum Outcome: Equatable, Sendable {
        case adjusted(gainDB: Float)
        case alreadyMatched
        case unsupported
    }

    @discardableResult
    public static func normalizeAll(volume: URL, fileManager fm: FileManager = .default,
                                    onProgress: (Int, Int) -> Void = { _, _ in }) -> SquidNormalizeReport {
        var report = SquidNormalizeReport()
        let files = wavFiles(in: SquidStick.rootURL(volume: volume), fileManager: fm)
        for (index, file) in files.enumerated() {
            onProgress(index, files.count)
            do {
                switch try normalize(file, fileManager: fm) {
                case .adjusted: report.adjusted += 1
                case .alreadyMatched: report.alreadyMatched += 1
                case .unsupported: report.skipped.append(file.lastPathComponent)
                }
            } catch { report.failed.append("\(file.lastPathComponent): \(error.localizedDescription)") }
        }
        onProgress(files.count, files.count)
        return report
    }

    /// Every WAV under a folder, without the hidden files Finder and macOS leave on a FAT stick (`._name`, `.DS_Store`).
    public static func wavFiles(in root: URL, fileManager fm: FileManager = .default) -> [URL] {
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in walker where ["wav", "wave"].contains(url.pathExtension.lowercased()) {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    @discardableResult
    public static func normalize(_ url: URL, fileManager fm: FileManager = .default) throws -> Outcome {
        let original = try Data(contentsOf: url)
        guard original.count >= 12, String(decoding: original[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: original[8..<12], as: UTF8.self) == "WAVE" else { return .unsupported }
        let chunks = WavChunks.parse(original)
        guard let fmt = chunks.first(where: { $0.id == "fmt " }), fmt.size >= 16,
              let data = chunks.first(where: { $0.id == "data" }) else { return .unsupported }
        let tag = Int(original.le16(fmt.dataStart)), channelCount = Int(original.le16(fmt.dataStart + 2))
        let bits = Int(original.le16(fmt.dataStart + 14))
        guard (tag == 1 || tag == 0xFFFE), bits == 16, channelCount >= 1 else { return .unsupported }

        let frames = data.size / (2 * channelCount)
        guard frames > 0 else { return .alreadyMatched }
        var channels = [[Float]](repeating: [Float](repeating: 0, count: frames), count: channelCount)
        for i in 0..<frames {
            for c in 0..<channelCount {
                channels[c][i] = Float(Int16(bitPattern: original.le16(data.dataStart + (i * channelCount + c) * 2))) / 32768
            }
        }
        let gain = LoudnessMatch.gainDB(channels: channels)
        guard abs(gain) >= toleranceDB else { return .alreadyMatched }

        let factor = Float(pow(10, Double(gain) / 20))
        var output = original
        output.withUnsafeMutableBytes { bytes in
            for i in 0..<(frames * channelCount) {
                let value = (Float(Int16(bitPattern: bytes.loadUnaligned(fromByteOffset: data.dataStart + i * 2, as: UInt16.self))) * factor).rounded()
                let clamped = Int16(max(-32768, min(32767, value)))
                bytes.storeBytes(of: UInt16(bitPattern: clamped).littleEndian, toByteOffset: data.dataStart + i * 2, as: UInt16.self)
            }
        }

        let temp = url.deletingLastPathComponent().appendingPathComponent(".clap-\(UUID().uuidString).tmp")
        do {
            try output.write(to: temp)
            // Everything outside the audio must come back as it was.
            let written = try Data(contentsOf: temp)
            guard written.count == original.count,
                  written[0..<data.dataStart] == original[0..<data.dataStart],
                  written[(data.dataStart + data.size)...] == original[(data.dataStart + data.size)...] else {
                throw CueWriteError.verificationFailed
            }
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        return .adjusted(gainDB: gain)
    }
}

private extension Data {
    func le16(_ o: Int) -> UInt16 {
        guard o >= 0, o + 2 <= count else { return 0 }
        return UInt16(self[startIndex + o]) | UInt16(self[startIndex + o + 1]) << 8
    }
}
