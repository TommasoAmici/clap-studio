import AVFoundation
import Foundation

/// How exported audio is written. The defaults keep each file's own format.
public struct ExportFormat: Equatable, Sendable {
    public enum BitDepth: String, CaseIterable, Sendable { case keep, int16, int24 }

    public var bitDepth: BitDepth = .keep
    public var mono = false
    /// Output sample rate, or nil to keep each file's own.
    public var sampleRate: Double?

    public init(bitDepth: BitDepth = .keep, mono: Bool = false, sampleRate: Double? = nil) {
        self.bitDepth = bitDepth; self.mono = mono; self.sampleRate = sampleRate
    }

    public var isDefault: Bool { self == ExportFormat() }
}

/// Writes trimmed (and optionally converted) copies as WAV files. Sources are only read.
public enum TrimExporter {
    public struct Item: Sendable {
        public var source: URL
        public var trim: SampleTrim?
        public var fileName: String
        public init(source: URL, trim: SampleTrim?, fileName: String) { self.source = source; self.trim = trim; self.fileName = fileName }
    }

    /// Writes the trimmed region of `source` to `destination` as a WAV file.
    /// `maxSeconds` cuts the result off at that length (before conversion). `declick` adds the short edge fades
    /// even without a trim (it is on whenever there is one).
    public static func write(source: URL, trim: SampleTrim?, format: ExportFormat, to destination: URL,
                             maxSeconds: Double? = nil, declick: Bool? = nil) throws {
        let file = try AVAudioFile(forReading: source)
        let native = file.processingFormat
        let fades = declick ?? (trim != nil)
        var buffer = try TrimRender.read(url: source, start: trim?.start ?? 0, end: trim?.end,
                                         fadeIn: fades ? SampleTrim.declick : 0,
                                         fadeOut: trim?.effectiveFadeOut ?? (fades ? SampleTrim.declick : 0),
                                         maxSeconds: maxSeconds)

        let channels = format.mono ? 1 : native.channelCount
        let rate = format.sampleRate ?? native.sampleRate
        if channels != native.channelCount || rate != native.sampleRate {
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false) else {
                throw AudioDecodeError.conversion("unsupported output format")
            }
            buffer = try AudioConvert.convert(buffer, to: target, highQuality: true)
        }

        let source = file.fileFormat.settings
        let sourceDepth = source[AVLinearPCMBitDepthKey] as? Int
        let sourceIsFloat = (source[AVLinearPCMIsFloatKey] as? Bool) ?? false
        let depth: Int, isFloat: Bool
        switch format.bitDepth {
        case .int16: (depth, isFloat) = (16, false)
        case .int24: (depth, isFloat) = (24, false)
        case .keep: (depth, isFloat) = sourceIsFloat ? (32, true) : (sourceDepth.map { min($0, 24) } ?? 16, false)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: depth, AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            let out = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try out.write(from: buffer)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Exports each item into `folder`. Files with no trim and no format change are copied as they are;
    /// the others are rendered to WAV (named `.wav`). Nothing existing is overwritten.
    public static func export(_ items: [Item], format: ExportFormat, to folder: URL, fileManager fm: FileManager = .default) -> SampleExporter.Report {
        var report = SampleExporter.Report()
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            report.failures = items.map { ($0.source, error.localizedDescription) }
            return report
        }
        for item in items {
            if item.trim == nil && format.isDefault {
                let r = SampleExporter.copy([(source: item.source, fileName: item.fileName)], to: folder, fileManager: fm)
                report.copied += r.copied; report.failures += r.failures
                continue
            }
            let name = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent + ".wav"
            let target = SampleExporter.uniqueURL(in: folder, fileName: name, fileManager: fm)
            do { try write(source: item.source, trim: item.trim, format: format, to: target); report.copied.append(target) }
            catch { report.failures.append((item.source, error.localizedDescription)) }
        }
        return report
    }
}
