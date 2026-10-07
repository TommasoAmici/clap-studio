import AVFoundation
import Foundation
import Testing
@testable import ClapCore

/// Writes a mono 16-bit WAV with a synthetic signal.
func writeTestWav(_ url: URL, seconds: Double, sampleRate: Double = 44100,
                  signal: (Double) -> Float) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    let n = AVAudioFrameCount(seconds * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
    buffer.frameLength = n
    for i in 0..<Int(n) { buffer.floatChannelData![0][i] = signal(Double(i) / sampleRate) }
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
    try file.write(from: buffer)
}

@Suite struct PipelineTests {
    @Test func decodesAndEmbedsAndPersists() async throws {
        let dir = TestSupport.tempDir()
        try writeTestWav(dir.appendingPathComponent("sine.wav"), seconds: 0.5) { Float(sin(2 * .pi * 440 * $0)) * 0.5 }
        try writeTestWav(dir.appendingPathComponent("sub/click.wav"), seconds: 0.3, sampleRate: 48000) {
            $0 < 0.002 ? 0.9 : 0
        }
        try Data([0, 1, 2]).write(to: dir.appendingPathComponent("broken.wav"))

        let dbPath = dir.appendingPathComponent("lib.sqlite").path
        let store = try LibraryStore(path: dbPath)
        let root = try store.addRoot(path: dir.path)
        try store.sync(rootID: root.id, scanned: FolderScanner.scan(root: dir)) { _ in nil }

        let pipeline = IndexingPipeline(store: store, embedder: HandcraftedEmbedder(), workers: 2, batchSize: 2)
        let ok = await pipeline.run(onProgress: { _ in })
        #expect(ok == 2)
        #expect(store.failedCount() == 1)

        // Relaunch: nothing left to do and nothing is re-embedded.
        let reopened = try LibraryStore(path: dbPath)
        #expect(reopened.pendingCount() == 0)
        let again = await IndexingPipeline(store: reopened, embedder: HandcraftedEmbedder()).run(onProgress: { _ in })
        #expect(again == 0)
        let samples = reopened.loadSamples()
        #expect(samples.count == 2)
        #expect(samples.first { $0.name == "sine" }?.duration ?? 0 > 0.49)
    }

    @Test func handcraftedEmbeddingSeparatesSoundTypes() throws {
        let extractor = LogMelExtractor()
        let embedder = HandcraftedEmbedder()
        func embed(_ f: (Double) -> Float, seconds: Double) throws -> [Float] {
            let n = Int(seconds * 32000)
            return try embedder.embed(extractor.extract(signal: (0..<n).map { f(Double($0) / 32000) }))
        }
        func dist(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }
        let low1 = try embed({ Float(sin(2 * .pi * 80 * $0)) * Float(exp(-$0 * 8)) }, seconds: 0.5)
        let low2 = try embed({ Float(sin(2 * .pi * 90 * $0)) * Float(exp(-$0 * 8)) }, seconds: 0.5)
        var rng = SplitMix64(seed: 1)
        let noise = (0..<16000).map { _ in rng.nextFloat() * 2 - 1 }
        let hat = try embedder.embed(extractor.extract(signal: noise.enumerated().map { $1 * Float(exp(-Double($0) / 32000 * 40)) }))
        #expect(dist(low1, low2) < dist(low1, hat))
    }
}
