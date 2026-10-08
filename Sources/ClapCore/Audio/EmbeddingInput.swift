import Foundation

/// The one place that turns a file into the signal an embedder sees. Indexing and query-by-example both use it,
/// so a dropped file embeds exactly like its library copy.
public struct EmbeddingInput {
    public let audio: AnalysisAudio
    /// Measured on the original audio, so level and length stay real.
    public let descriptors: SoundDescriptors
    /// Standardised signal for the embedder.
    public let signal: [Float]

    /// Decodes enough audio for both the descriptors and the embedder's window.
    public static func load(url: URL, frontEnd fe: FrontEndConfig, analyzer: DescriptorAnalyzer) throws -> EmbeddingInput {
        let rate = Double(fe.sampleRate)
        let audio = try AudioDecoder.decodeForAnalysis(url: url, maxSeconds: max(fe.analysisSeconds, DescriptorAnalyzer.analysisSeconds),
                                                       sampleRate: rate)
        let descriptors = analyzer.analyze(samples: audio.samples, sampleRate: rate, fileDuration: audio.duration)
        // Loops keep their silence: it is part of the bar.
        let signal = SamplePreprocessor.prepare(audio.samples, sampleRate: rate, trimSilence: !descriptors.isLoop)
        return EmbeddingInput(audio: audio, descriptors: descriptors, signal: signal)
    }
}
