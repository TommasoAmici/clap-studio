import Accelerate
import Foundation

/// Log-mel spectrogram of the analysis window, shaped (frames x nMels).
public struct MelSpectrogram: Sendable {
    public let values: [Float]
    public let frames: Int
    /// Frames that contain real signal (the rest is padding).
    public let validFrames: Int
    /// Seconds of real audio in the analysis window.
    public let validSeconds: Double
    public let bands: Int
    public static let nMels = LogMelExtractor.nMels   // PANNs default
}

/// Parameters of a log-mel front end. A neural model must be fed the exact front end it was trained with.
public struct FrontEndConfig: Sendable, Equatable {
    public var sampleRate: Int
    public var analysisSeconds: Double
    public var nFFT: Int
    public var hop: Int
    public var nMels: Int
    public var fMin: Double
    public var fMax: Double
    /// Short clips are tiled and zero-padded to the full window (CLAP's "repeatpad"),
    /// instead of leaving the tail as silence.
    public var repeatPad: Bool

    public var analysisSamples: Int { Int(Double(sampleRate) * analysisSeconds) }
    public var nBins: Int { nFFT / 2 + 1 }
    public var frameCount: Int { 1 + analysisSamples / hop }

    /// PANNs CNN14: 32 kHz, 4 s, hop 320.
    public static let panns = FrontEndConfig(sampleRate: 32_000, analysisSeconds: 4, nFFT: 1024, hop: 320,
                                             nMels: 64, fMin: 50, fMax: 14_000, repeatPad: false)
    /// LAION-CLAP (HTSAT, unfused): 48 kHz, 10 s, hop 480, repeat-padded.
    public static let clap = FrontEndConfig(sampleRate: 48_000, analysisSeconds: 10, nFFT: 1024, hop: 480,
                                            nMels: 64, fMin: 50, fMax: 14_000, repeatPad: true)
}

/// Slaney-scale log-mel front end (librosa/HF style), configured by `FrontEndConfig`.
/// Not thread-safe: use one extractor per worker.
public final class LogMelExtractor {
    // PANNs defaults, kept for the DSP fallback embedder.
    public static let sampleRate = FrontEndConfig.panns.sampleRate
    public static let analysisSamples = FrontEndConfig.panns.analysisSamples
    public static let nFFT = FrontEndConfig.panns.nFFT
    public static let hop = FrontEndConfig.panns.hop
    public static let nMels = FrontEndConfig.panns.nMels
    public static let nBins = FrontEndConfig.panns.nBins
    public static let frameCount = FrontEndConfig.panns.frameCount   // 401

    public let config: FrontEndConfig
    private let setup: vDSP_DFT_Setup
    private let window: [Float]
    private let filters: [Float]

    public init(config: FrontEndConfig = .panns) {
        self.config = config
        let n = config.nFFT
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
        window = (0..<n).map { 0.5 - 0.5 * cosf(2 * .pi * Float($0) / Float(n)) }   // periodic Hann
        filters = Self.melFilterbank(config)
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    public func extract(signal: [Float]) -> MelSpectrogram {
        let c = config
        let L = c.analysisSamples, half = c.nFFT / 2, hop = c.hop
        let signal = c.repeatPad ? Self.repeatPadded(signal, to: L) : signal
        let valid = min(signal.count, L)

        var padded = [Float](repeating: 0, count: L + c.nFFT)
        for i in 0..<valid { padded[half + i] = signal[i] }
        for i in 0..<half where 1 + (half - 1 - i) < L { padded[i] = padded[half + (half - i)] }   // reflect left
        for j in 0..<half { padded[half + L + j] = padded[half + L - 2 - j] }                       // reflect right

        let frames = c.frameCount, bins = c.nBins, mels = c.nMels
        var power = [Float](repeating: 0, count: frames * bins)
        var framed = [Float](repeating: 0, count: c.nFFT)
        power.withUnsafeMutableBufferPointer { pw in
            for t in 0..<frames {
                padded.withUnsafeBufferPointer { p in
                    vDSP.multiply(UnsafeBufferPointer(rebasing: p[(t * hop)..<(t * hop + c.nFFT)]),
                                  window, result: &framed)
                }
                powerSpectrum(framed, into: pw.baseAddress! + t * bins)
            }
        }

        var mel = [Float](repeating: 0, count: frames * mels)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(frames), Int32(mels), Int32(bins),
                    1, power, Int32(bins), filters, Int32(bins), 0, &mel, Int32(mels))
        for i in 0..<mel.count { mel[i] = 10 * log10f(max(mel[i], 1e-10)) }

        let validFrames = c.repeatPad ? frames : min(frames, valid / hop + 1)
        // Fill padding frames with the floor of the real signal so edges stay smooth.
        let floorValue = mel[0..<(validFrames * mels)].min() ?? -100
        if validFrames < frames {
            for i in (validFrames * mels)..<mel.count { mel[i] = floorValue }
        }
        return MelSpectrogram(values: mel, frames: frames, validFrames: validFrames,
                              validSeconds: Double(valid) / Double(c.sampleRate), bands: mels)
    }

    /// CLAP "repeatpad": tile the clip as many whole times as fit, then zero-pad to `length`.
    static func repeatPadded(_ signal: [Float], to length: Int) -> [Float] {
        guard !signal.isEmpty, signal.count < length else { return signal }
        var out = [Float]()
        out.reserveCapacity(length)
        for _ in 0..<(length / signal.count) { out.append(contentsOf: signal) }
        out.append(contentsOf: [Float](repeating: 0, count: length - out.count))
        return out
    }

    /// |DFT|^2 of one windowed frame (nFFT real samples -> nBins powers).
    func powerSpectrum(_ frame: [Float], into out: UnsafeMutablePointer<Float>) {
        let half = config.nFFT / 2
        var re = [Float](repeating: 0, count: half), im = re
        var outRe = re, outIm = re
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBufferPointer { f in
                    f.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
            }
        }
        vDSP_DFT_Execute(setup, re, im, &outRe, &outIm)
        // vDSP's real DFT output is scaled by 2; DC and Nyquist are packed in bin 0.
        out[0] = (outRe[0] * 0.5) * (outRe[0] * 0.5)
        out[half] = (outIm[0] * 0.5) * (outIm[0] * 0.5)
        for k in 1..<half { out[k] = 0.25 * (outRe[k] * outRe[k] + outIm[k] * outIm[k]) }
    }

    // MARK: mel filterbank (librosa, Slaney scale and normalization)

    static func hzToMel(_ f: Double) -> Double {
        let fsp = 200.0 / 3, minLogHz = 1000.0, minLogMel = minLogHz / fsp, logstep = log(6.4) / 27
        return f < minLogHz ? f / fsp : minLogMel + log(f / minLogHz) / logstep
    }

    static func melToHz(_ m: Double) -> Double {
        let fsp = 200.0 / 3, minLogHz = 1000.0, minLogMel = minLogHz / fsp, logstep = log(6.4) / 27
        return m < minLogMel ? m * fsp : minLogHz * exp(logstep * (m - minLogMel))
    }

    static func melFilterbank(fMin: Double = 50, fMax: Double = 14_000) -> [Float] {
        var c = FrontEndConfig.panns
        c.fMin = fMin; c.fMax = fMax
        return melFilterbank(c)
    }

    static func melFilterbank(_ c: FrontEndConfig) -> [Float] {
        let mels = c.nMels, bins = c.nBins, sampleRate = c.sampleRate, nFFT = c.nFFT
        let lo = hzToMel(c.fMin), hi = hzToMel(c.fMax)
        let melF = (0..<(mels + 2)).map { melToHz(lo + (hi - lo) * Double($0) / Double(mels + 1)) }
        let fftFreqs = (0..<bins).map { Double($0) * Double(sampleRate) / Double(nFFT) }
        var w = [Float](repeating: 0, count: mels * bins)
        for i in 0..<mels {
            let fdiffLow = melF[i + 1] - melF[i], fdiffHigh = melF[i + 2] - melF[i + 1]
            let enorm = 2.0 / (melF[i + 2] - melF[i])
            for k in 0..<bins {
                let lower = (fftFreqs[k] - melF[i]) / fdiffLow
                let upper = (melF[i + 2] - fftFreqs[k]) / fdiffHigh
                w[i * bins + k] = Float(max(0, min(lower, upper)) * enorm)
            }
        }
        return w
    }
}
