import Foundation
import Testing
@testable import ClapCore

/// Checks the Swift pipeline against ground truth produced by librosa and Hugging Face
/// (see tools/make_references.py).
@Suite struct ReferenceTests {
    static func testSignal(rate: Int, seconds: Double = 0.5) -> [Float] {
        (0..<Int(Double(rate) * seconds)).map { i in
            let t = Double(i) / Double(rate)
            return Float(0.5 * sin(2 * .pi * 220 * t) * exp(-6 * t) + 0.2 * sin(2 * .pi * 3000 * t) * exp(-20 * t))
        }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return dot / (sqrtf(na) * sqrtf(nb) + 1e-12)
    }

    static func maxDiff(_ mel: MelSpectrogram, rows: [Int], expected: [[Float]]) -> Float {
        var worst: Float = 0
        for (r, ref) in zip(rows, expected) {
            for m in 0..<mel.bands { worst = max(worst, abs(mel.values[r * mel.bands + m] - ref[m])) }
        }
        return worst
    }

    @Test func pannsFrontEndMatchesLibrosa() {
        let mel = LogMelExtractor(config: .panns).extract(signal: Self.testSignal(rate: 32_000))
        #expect(mel.frames == 401)
        let worst = Self.maxDiff(mel, rows: Reference.pannsRows, expected: Reference.pannsMel)
        #expect(worst < 0.05, "max |dB difference| \(worst)")
    }

    @Test func clapFrontEndMatchesHuggingFace() {
        let mel = LogMelExtractor(config: .clap).extract(signal: Self.testSignal(rate: 48_000))
        #expect(mel.frames == 1001 && mel.bands == 64)
        let worst = Self.maxDiff(mel, rows: Reference.clapRows, expected: Reference.clapMel)
        #expect(worst < 0.05, "max |dB difference| \(worst)")
    }

    @Test func tokenizerMatchesHuggingFace() throws {
        guard let vocab = ModelLocator.resource("clap_vocab.json"), let merges = ModelLocator.resource("clap_merges.txt") else {
            return   // tokenizer files not exported on this machine
        }
        let tokenizer = try BPETokenizer(vocabURL: vocab, mergesURL: merges)
        for (phrase, expected) in zip(Reference.phrases, Reference.tokenIDs) {
            #expect(tokenizer.encode(phrase, length: 48).ids == expected, "\(phrase)")
        }
    }

    @Test func clapAudioEmbeddingMatchesPyTorch() throws {
        guard case .success(let embedder) = ClapEmbedder.load() else { return }
        let mel = LogMelExtractor(config: embedder.frontEnd).extract(signal: Self.testSignal(rate: 48_000))
        let cos = Self.cosine(try embedder.embed(mel), Reference.clapEmbedding)
        #expect(cos > 0.99, "cosine \(cos)")
    }

    @Test func clapTextEmbeddingMatchesPyTorch() throws {
        guard case .success(let encoder) = ClapTextEncoder.load() else { return }
        for (phrase, expected) in zip(Reference.phrases, Reference.textEmbeddings) {
            let cos = Self.cosine(try encoder.embed(phrase), expected)
            #expect(cos > 0.99, "\(phrase): cosine \(cos)")
        }
    }
}
