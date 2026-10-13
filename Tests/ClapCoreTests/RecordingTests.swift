import Foundation
import Testing
@testable import ClapCore

@Suite struct RecordingTests {
    @Test func aRecordingNeedsLengthAndSound() {
        var stats = RecordingStats(sampleRate: 48000)
        #expect(stats.problem == .tooShort, "nothing recorded yet")
        stats.add(frames: 12000, peak: 0.5)                       // a quarter of a second
        #expect(stats.problem == .tooShort)
        stats.add(frames: 24000, peak: 0.2)
        #expect(abs(stats.seconds - 0.75) < 1e-9 && stats.peak == 0.5)
        #expect(stats.problem == nil)
    }

    @Test func aSilentInputIsReported() {
        var stats = RecordingStats(sampleRate: 44100)
        stats.add(frames: 44100, peak: 0.00001)                   // about -100 dB
        #expect(stats.problem == .silent)
        stats.add(frames: 100, peak: 0.01)                        // -40 dB
        #expect(stats.problem == nil && abs(stats.peakDB - (-40)) < 0.01)
    }

    @Test func peakLooksAtEveryChannel() {
        var left: [Float] = [0.1, -0.2, 0.05], right: [Float] = [0.0, 0.0, -0.9]
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                var pointers = [l.baseAddress!, r.baseAddress!]
                let peak = pointers.withUnsafeMutableBufferPointer {
                    RecordingStats.peak(of: UnsafePointer($0.baseAddress!), channelCount: 2, frames: 3)
                }
                #expect(abs(peak - 0.9) < 1e-6)
            }
        }
    }
}
