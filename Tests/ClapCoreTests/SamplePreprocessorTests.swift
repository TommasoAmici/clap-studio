import Foundation
import Testing
@testable import ClapCore

@Suite struct SamplePreprocessorTests {
    private let rate = 8_000.0

    /// A decaying 440 Hz tone that starts on the first sample.
    private func burst(seconds: Double = 0.3, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * rate)).map { i in
            let t = Double(i) / rate
            return amplitude * Float(sin(2 * .pi * 440 * t) * exp(-20 * t))
        }
    }

    private func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    private func rmsDB(_ x: [Float]) -> Double {
        let power = x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)
        return 10 * log10(power)
    }

    private func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    @Test func levelDoesNotChangeThePreparedSignal() {
        let loud = SamplePreprocessor.prepare(burst(amplitude: 0.5), sampleRate: rate)
        let quiet = SamplePreprocessor.prepare(burst(amplitude: 0.125), sampleRate: rate)
        #expect(loud.count == quiet.count)
        let worst = zip(loud, quiet).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
        #expect(worst < 1e-5, "a quieter copy of a sound prepares to the same signal")
    }

    @Test func leadingSilenceDoesNotChangeThePreparedSignal() {
        let long = SamplePreprocessor.prepare(silence(1.0) + burst(), sampleRate: rate)
        let short = SamplePreprocessor.prepare(silence(0.3) + burst(), sampleRate: rate)
        #expect(long.count == short.count)
        let worst = zip(long, short).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
        #expect(worst < 1e-5, "however much silence came before the sound")
    }

    @Test func trailingSilenceDoesNotChangeThePreparedSignal() {
        let long = SamplePreprocessor.prepare(burst() + silence(1.0), sampleRate: rate)
        let short = SamplePreprocessor.prepare(burst() + silence(0.3), sampleRate: rate)
        #expect(long.count == short.count)
        let worst = zip(long, short).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
        #expect(worst < 1e-5, "however much silence came after the sound")
    }

    @Test func keepsAFewMillisecondsBeforeTheAttack() {
        // Five milliseconds at 8 kHz is 40 samples of silence before the attack.
        let attack = [Float](repeating: 0.5, count: 800)
        let prepared = SamplePreprocessor.prepare(silence(0.3) + attack, sampleRate: rate)
        let leading = prepared.prefix(while: { $0 == 0 }).count
        #expect(abs(leading - 40) <= 1)
    }

    @Test func loopsKeepTheirSilenceButStillGetTheLevel() {
        // Silence inside a loop is part of its bar, so it is not cut; the level still matches everything else.
        // A steady tone (low crest factor) so the level target is reachable under the peak ceiling.
        let tone = (0..<2_400).map { Float(0.05 * sin(2 * .pi * 440 * Double($0) / rate)) }
        let loop = silence(0.2) + tone + silence(0.2)
        let prepared = SamplePreprocessor.prepare(loop, sampleRate: rate, trimSilence: false)
        #expect(prepared.count == loop.count)
        // The burst starts with a zero sample, so the leading run is the 1600 silent samples plus one.
        #expect(abs(prepared.prefix(while: { $0 == 0 }).count - 1_600) <= 1, "the leading silence stays")
        #expect(abs(rmsDB(prepared) - SamplePreprocessor.targetRMSDB) < 0.1)
    }

    @Test func preRollIsTheSameLengthAtEverySampleRate() {
        for rate in [8_000.0, 22_050.0, 32_000.0, 44_100.0, 48_000.0] {
            let attack = [Float](repeating: 0.5, count: Int(rate * 0.1))
            let prepared = SamplePreprocessor.prepare([Float](repeating: 0, count: Int(rate * 0.2)) + attack, sampleRate: rate)
            let leading = prepared.prefix(while: { $0 == 0 }).count
            #expect(leading == Int((SamplePreprocessor.preRollSeconds * rate).rounded()), "at \(rate) Hz")
        }
    }

    @Test func nonFiniteSamplesAreReturnedUnchanged() {
        for bad in [Float.infinity, -Float.infinity, Float.nan] {
            let signal = burst() + [bad] + burst()
            let prepared = SamplePreprocessor.prepare(signal, sampleRate: rate)
            #expect(prepared.count == signal.count)
            #expect(prepared.enumerated().allSatisfy { $1 == signal[$0] || ($1.isNaN && signal[$0].isNaN) },
                    "\(bad) must not turn the whole signal into NaN")
        }
    }

    @Test func silenceStaysSilent() {
        let quiet = silence(0.2)
        #expect(SamplePreprocessor.prepare(quiet, sampleRate: rate) == quiet)
    }

    @Test func activePartReachesTheTargetLevel() {
        let prepared = SamplePreprocessor.prepare(burst(amplitude: 0.05), sampleRate: rate)
        #expect(abs(rmsDB(prepared) - SamplePreprocessor.targetRMSDB) < 0.1)
    }

    @Test func peakNeverGoesAboveTheCeiling() {
        // A single loud click: matching its RMS would push the peak over full scale.
        let click = silence(0.1) + [0.5] + silence(0.1)
        let prepared = SamplePreprocessor.prepare(click, sampleRate: rate)
        let ceiling = pow(10, SamplePreprocessor.peakCeilingDB / 20)
        #expect(Double(peak(prepared)) <= ceiling + 1e-6)
    }

    @Test func veryQuietFilesAreBoostedAtMostTheCap() {
        let quiet = burst(amplitude: 1e-4)
        let prepared = SamplePreprocessor.prepare(quiet, sampleRate: rate)
        let gain = Double(peak(prepared)) / Double(peak(quiet))
        #expect(abs(gain / pow(10, SamplePreprocessor.maxBoostDB / 20) - 1) < 1e-3,
                "the noise floor of a near-silent file is not boosted to the target")
    }
}

@Suite struct EmbeddingInputTests {
    private func embedding(_ url: URL) throws -> (vector: [Float], loudnessDB: Double) {
        // The same input path indexing and query-by-example use.
        let embedder = HandcraftedEmbedder()
        let input = try EmbeddingInput.load(url: url, frontEnd: embedder.frontEnd, analyzer: DescriptorAnalyzer())
        let vector = try embedder.embed(LogMelExtractor(config: embedder.frontEnd).extract(signal: input.signal))
        return (vector, input.descriptors.loudnessDB)
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let na = a.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        let nb = b.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return dot / (na * nb)
    }

    @Test func levelAndPaddingDoNotChangeTheEmbeddingButLoudnessStaysReal() throws {
        let dir = TestSupport.tempDir()
        let plain = dir.appendingPathComponent("plain.wav")
        let padded = dir.appendingPathComponent("padded.wav")
        try writeTestWav(plain, seconds: 0.4, sampleRate: 48_000) { t in
            Float(sin(2 * .pi * 180 * t) * exp(-40 * t)) * 0.4
        }
        try writeTestWav(padded, seconds: 1.8, sampleRate: 48_000) { t in
            let u = t - 1.0   // a second of silence, then the same 0.4 s sound 20 dB quieter
            return u < 0 || u >= 0.4 ? 0 : Float(sin(2 * .pi * 180 * u) * exp(-40 * u)) * 0.04
        }

        let a = try embedding(plain), b = try embedding(padded)
        #expect(cosine(a.vector, b.vector) > 0.99, "same sound, different level and padding")
        #expect(a.loudnessDB - b.loudnessDB > 15, "the loudness descriptor still measures the original level")
    }
}
