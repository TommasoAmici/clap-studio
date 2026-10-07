import CoreML
import Foundation

/// LAION-CLAP (HTSAT) audio tower on Core ML: 10 s log-mel in, 512-d unit embedding out.
/// The same space holds text embeddings, which enables "describe a sound" search.
public final class ClapEmbedder: EmbeddingProvider, @unchecked Sendable {
    public static let audioModelName = "CLAPAudio"
    public static let textModelName = "CLAPText"
    public static let versionTag = "laion-clap-htsat-v1"

    public let version = ClapEmbedder.versionTag
    public let dimension = 512
    public var frontEnd: FrontEndConfig { .clap }

    private let model: MLModel

    init(model: MLModel) { self.model = model }

    public static func load() -> Result<ClapEmbedder, ModelLoadError> {
        do {
            return .success(ClapEmbedder(model: try ModelLocator.load(audioModelName)))
        } catch let error as ModelLoadError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    public func embed(_ mel: MelSpectrogram) throws -> [Float] {
        let input = try MLMultiArray(shape: [1, 1, NSNumber(value: mel.frames), NSNumber(value: mel.bands)],
                                     dataType: .float32)
        mel.values.withUnsafeBufferPointer { src in
            input.dataPointer.copyMemory(from: src.baseAddress!, byteCount: src.count * MemoryLayout<Float>.size)
        }
        let features = try MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: input)])
        let output = try model.prediction(from: features)
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw ModelLoadError.failed("missing 'embedding' output")
        }
        var v = array.floatValues()
        l2Normalize(&v)
        return v
    }
}

/// CLAP text tower: turns a description ("punchy 808 kick") into a point in the audio embedding space.
public final class ClapTextEncoder: @unchecked Sendable {
    public static let tokenCount = 48   // must match tools/export_clap.py

    private let model: MLModel
    private let tokenizer: BPETokenizer

    init(model: MLModel, tokenizer: BPETokenizer) {
        self.model = model
        self.tokenizer = tokenizer
    }

    public static func load() -> Result<ClapTextEncoder, ModelLoadError> {
        guard ModelLocator.exists(ClapEmbedder.textModelName),
              let vocab = ModelLocator.resource("clap_vocab.json"),
              let merges = ModelLocator.resource("clap_merges.txt") else {
            return .failure(.notFound(ClapEmbedder.textModelName))
        }
        do {
            let tokenizer = try BPETokenizer(vocabURL: vocab, mergesURL: merges)
            return .success(ClapTextEncoder(model: try ModelLocator.load(ClapEmbedder.textModelName), tokenizer: tokenizer))
        } catch let error as ModelLoadError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    public func embed(_ text: String) throws -> [Float] {
        let n = Self.tokenCount
        let (ids, mask) = tokenizer.encode(text, length: n)
        let idArray = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32)
        let maskArray = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32)
        for i in 0..<n {
            idArray[i] = NSNumber(value: ids[i])
            maskArray[i] = NSNumber(value: mask[i])
        }
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: idArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])
        let output = try model.prediction(from: features)
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw ModelLoadError.failed("missing 'embedding' output")
        }
        var v = array.floatValues()
        l2Normalize(&v)
        return v
    }
}
