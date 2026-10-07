import Accelerate
import Foundation

/// Hann-windowed magnitude spectra via vDSP. Not thread-safe: one instance per worker.
final class SpectrumAnalyzer {
    let nFFT: Int
    var bins: Int { nFFT / 2 + 1 }
    private let setup: vDSP_DFT_Setup
    private let window: [Float]

    init(nFFT: Int) {
        self.nFFT = nFFT
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD)!
        window = (0..<nFFT).map { 0.5 - 0.5 * cosf(2 * .pi * Float($0) / Float(nFFT)) }
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    /// Magnitudes of the frame starting at `start` (zero-padded before the start and past the end).
    func magnitudes(of signal: [Float], start: Int, into out: inout [Float]) {
        let half = nFFT / 2
        var frame = [Float](repeating: 0, count: nFFT)
        for i in max(0, -start)..<nFFT {
            let index = start + i
            if index >= signal.count { break }
            frame[i] = signal[index] * window[i]
        }

        var re = [Float](repeating: 0, count: half), im = re, outRe = re, outIm = re
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
        // vDSP's real transform is scaled by 2; DC and Nyquist are packed into bin 0.
        out[0] = abs(outRe[0]) * 0.5
        out[half] = abs(outIm[0]) * 0.5
        for k in 1..<half { out[k] = 0.5 * sqrtf(outRe[k] * outRe[k] + outIm[k] * outIm[k]) }
    }
}
