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
    public static let nMels = LogMelExtractor.nMels
}

/// PANNs-compatible log-mel front end (n_fft 1024, hop 320, 64 mels, 50-14000 Hz, 32 kHz).
/// Not thread-safe: use one extractor per worker.
public final class LogMelExtractor {
    public static let sampleRate = 32_000
    public static let analysisSamples = 128_000          // 4 s
    public static let nFFT = 1024
    public static let hop = 320
    public static let nMels = 64
    public static let nBins = nFFT / 2 + 1
    public static let frameCount = 1 + analysisSamples / hop   // 401

    private let setup: vDSP_DFT_Setup
    private let window: [Float]
    private let filters: [Float]

    public init() {
        let n = Self.nFFT
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
        window = (0..<n).map { 0.5 - 0.5 * cosf(2 * .pi * Float($0) / Float(n)) }   // periodic Hann
        filters = Self.melFilterbank()
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    public func extract(signal: [Float]) -> MelSpectrogram {
        let L = Self.analysisSamples, half = Self.nFFT / 2, hop = Self.hop
        let valid = min(signal.count, L)

        var padded = [Float](repeating: 0, count: L + Self.nFFT)
        for i in 0..<valid { padded[half + i] = signal[i] }
        for i in 0..<half where 1 + (half - 1 - i) < L { padded[i] = padded[half + (half - i)] }   // reflect left
        for j in 0..<half { padded[half + L + j] = padded[half + L - 2 - j] }                       // reflect right

        let frames = Self.frameCount, bins = Self.nBins, mels = Self.nMels
        var power = [Float](repeating: 0, count: frames * bins)
        var framed = [Float](repeating: 0, count: Self.nFFT)
        power.withUnsafeMutableBufferPointer { pw in
            for t in 0..<frames {
                padded.withUnsafeBufferPointer { p in
                    vDSP.multiply(UnsafeBufferPointer(rebasing: p[(t * hop)..<(t * hop + Self.nFFT)]),
                                  window, result: &framed)
                }
                powerSpectrum(framed, into: pw.baseAddress! + t * bins)
            }
        }

        var mel = [Float](repeating: 0, count: frames * mels)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(frames), Int32(mels), Int32(bins),
                    1, power, Int32(bins), filters, Int32(bins), 0, &mel, Int32(mels))
        for i in 0..<mel.count { mel[i] = 10 * log10f(max(mel[i], 1e-10)) }

        let validFrames = min(frames, valid / hop + 1)
        // Fill padding frames with the floor of the real signal so edges stay smooth.
        let floorValue = mel[0..<(validFrames * mels)].min() ?? -100
        if validFrames < frames {
            for i in (validFrames * mels)..<mel.count { mel[i] = floorValue }
        }
        return MelSpectrogram(values: mel, frames: frames, validFrames: validFrames,
                              validSeconds: Double(valid) / Double(Self.sampleRate))
    }

    /// |DFT|^2 of one windowed frame (nFFT real samples -> nBins powers).
    func powerSpectrum(_ frame: [Float], into out: UnsafeMutablePointer<Float>) {
        let half = Self.nFFT / 2
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
        let mels = nMels, bins = nBins
        let lo = hzToMel(fMin), hi = hzToMel(fMax)
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
