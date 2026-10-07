import AVFoundation
import Foundation

/// Decodes whole files to the playback format and keeps recent ones (LRU, byte-capped)
/// so hover-to-play on already-seen samples is instant.
public final class AudioBufferCache: @unchecked Sendable {
    public static let maxSeconds = 120.0

    private let lock = NSLock()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var order: [String] = []          // least recently used first
    private var bytes = 0
    private let capacity: Int
    public let format: AVAudioFormat

    public init(sampleRate: Double, capacityBytes: Int = 384 * 1024 * 1024) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        capacity = capacityBytes
    }

    public func cached(_ url: URL) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard let b = buffers[url.path] else { return nil }
        order.removeAll { $0 == url.path }
        order.append(url.path)
        return b
    }

    public func buffer(for url: URL) throws -> AVAudioPCMBuffer {
        if let hit = cached(url) { return hit }
        let decoded = try Self.decode(url: url, to: format)
        store(decoded, for: url)
        return decoded
    }

    private func store(_ buffer: AVAudioPCMBuffer, for url: URL) {
        let size = Int(buffer.frameLength) * Int(format.channelCount) * MemoryLayout<Float>.size
        lock.lock(); defer { lock.unlock() }
        if buffers[url.path] == nil { bytes += size }
        buffers[url.path] = buffer
        order.removeAll { $0 == url.path }
        order.append(url.path)
        while bytes > capacity, order.count > 1 {
            let oldest = order.removeFirst()
            if let b = buffers.removeValue(forKey: oldest) {
                bytes -= Int(b.frameLength) * Int(format.channelCount) * MemoryLayout<Float>.size
            }
        }
    }

    static func decode(url: URL, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let src = file.processingFormat
        let frames = AVAudioFrameCount(min(file.length, Int64(maxSeconds * src.sampleRate)))
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames) else {
            throw AudioDecodeError.empty
        }
        try file.read(into: input, frameCount: frames)
        if src.sampleRate == format.sampleRate && src.channelCount == format.channelCount
            && src.commonFormat == format.commonFormat && !src.isInterleaved { return input }

        guard let converter = AVAudioConverter(from: src, to: format) else {
            throw AudioDecodeError.conversion("unsupported format")
        }
        let capacity = AVAudioFrameCount(Double(frames) * format.sampleRate / src.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioDecodeError.conversion("buffer allocation")
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied { outStatus.pointee = .endOfStream; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error { throw AudioDecodeError.conversion(error?.localizedDescription ?? "unknown") }
        return output
    }

    /// Min/max envelope for drawing: `bins` pairs (min, max) over the first channel mix.
    public static func peaks(of buffer: AVAudioPCMBuffer, bins: Int) -> [Float] {
        let frames = Int(buffer.frameLength)
        guard frames > 0, bins > 0, let data = buffer.floatChannelData else { return [] }
        let channels = Int(buffer.format.channelCount)
        var out = [Float](repeating: 0, count: bins * 2)
        for b in 0..<bins {
            let lo = frames * b / bins, hi = max(lo + 1, frames * (b + 1) / bins)
            var mn: Float = 0, mx: Float = 0
            for c in 0..<channels {
                for i in lo..<min(hi, frames) { let v = data[c][i]; mn = min(mn, v); mx = max(mx, v) }
            }
            out[b * 2] = mn; out[b * 2 + 1] = mx
        }
        return out
    }
}
