import Foundation
import Testing
@testable import ClapCore

@Suite struct LogMelTests {
    private func sine(_ hz: Float, seconds: Float, amp: Float = 1) -> [Float] {
        let n = Int(seconds * 32000)
        return (0..<n).map { amp * sinf(2 * .pi * hz * Float($0) / 32000) }
    }

    @Test func powerSpectrumMatchesTheory() {
        // Hann window: peak magnitude = A * sum(w) / 2 = A * N / 4 for a bin-centred sine.
        let ex = LogMelExtractor()
        let n = LogMelExtractor.nFFT
        let window = (0..<n).map { 0.5 - 0.5 * cosf(2 * .pi * Float($0) / Float(n)) }
        let frame = (0..<n).map { window[$0] * sinf(2 * .pi * 32 * Float($0) / Float(n)) }
        var out = [Float](repeating: 0, count: LogMelExtractor.nBins)
        ex.powerSpectrum(frame, into: &out)
        let peak = out.enumerated().max { $0.element < $1.element }!
        #expect(peak.offset == 32)
        #expect(abs(peak.element - 65536) / 65536 < 0.01)
    }

    @Test func shapeAndValidFrames() {
        let ex = LogMelExtractor()
        let mel = ex.extract(signal: sine(1000, seconds: 1))
        #expect(mel.frames == 401 && mel.values.count == 401 * 64)
        #expect(mel.validFrames == 32000 / 320 + 1)
        #expect(mel.validSeconds == 1)
    }

    @Test func sinePeaksInExpectedMelBand() {
        let ex = LogMelExtractor()
        func peakBand(_ hz: Float) -> Int {
            let mel = ex.extract(signal: sine(hz, seconds: 1))
            let row = Array(mel.values[(100 * 64)..<(101 * 64)])
            return row.enumerated().max { $0.element < $1.element }!.offset
        }
        #expect(peakBand(200) < peakBand(1000))
        #expect(peakBand(1000) < peakBand(8000))
    }

    @Test func filterbankIsNormalized() {
        let fb = LogMelExtractor.melFilterbank()
        #expect(fb.count == 64 * 513)
        #expect(fb.allSatisfy { $0 >= 0 })
        #expect((0..<64).allSatisfy { i in fb[(i * 513)..<((i + 1) * 513)].reduce(0, +) > 0 })
    }
}
