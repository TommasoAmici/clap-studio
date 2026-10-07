import Foundation

/// Turns a log-mel spectrogram into a fixed-size vector where similar sounds are close.
public protocol EmbeddingProvider: Sendable {
    /// Stored with every embedding; a change triggers re-embedding.
    var version: String { get }
    var dimension: Int { get }
    /// The log-mel front end this model expects.
    var frontEnd: FrontEndConfig { get }
    func embed(_ mel: MelSpectrogram) throws -> [Float]
}

public extension EmbeddingProvider {
    var frontEnd: FrontEndConfig { .panns }
}

public enum EmbedderFactory {
    public struct Choice: Sendable {
        public let provider: EmbeddingProvider
        /// True when the neural model was not found and the DSP fallback is used.
        public let isFallback: Bool
        public let note: String
    }

    /// Preference: LAION-CLAP, then PANNs CNN14, then the built-in DSP features.
    public static func make() -> Choice {
        switch ClapEmbedder.load() {
        case .success(let model):
            return Choice(provider: model, isFallback: false, note: "LAION-CLAP model loaded")
        case .failure(.notFound):
            break
        case .failure(let error):
            NSLog("CLAP model unavailable: \(error)")
        }
        switch CoreMLEmbedder.load() {
        case .success(let model):
            return Choice(provider: model, isFallback: false, note: "CNN14 model loaded")
        case .failure(let error):
            return Choice(provider: HandcraftedEmbedder(), isFallback: true,
                          note: "Using built-in audio features (\(error)). Run tools/export_clap.py for better similarity.")
        }
    }
}

func l2Normalize(_ v: inout [Float]) {
    var sum: Float = 0
    for x in v { sum += x * x }
    let norm = sqrtf(sum)
    if norm > 1e-12 { for i in 0..<v.count { v[i] /= norm } }
}
