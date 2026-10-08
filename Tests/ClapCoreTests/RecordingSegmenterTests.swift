import Foundation
import Testing
@testable import ClapCore

@Suite struct RecordingSegmenterTests {
    private let hop = 0.05

    /// Envelope with `loud` stretches (start, end seconds) at -20 dB over a -80 dB floor.
    private func envelope(seconds: Double, loud: [(Double, Double)]) -> [Float] {
        (0..<Int(seconds / hop)).map { i in
            let t = Double(i) * hop
            return loud.contains { t >= $0.0 && t < $0.1 } ? -20 : -80
        }
    }

    @Test func splitsAtSilenceAndPadsEdges() {
        let env = envelope(seconds: 20, loud: [(2, 4), (8, 9.5)])
        let spans = RecordingSegmenter.segments(envelopeDB: env, hop: hop, duration: 20)
        #expect(spans.count == 2)
        #expect(abs(spans[0].start - 1.9) < 0.06 && abs(spans[0].end - 4.1) < 0.06)
        #expect(abs(spans[1].start - 7.9) < 0.06 && abs(spans[1].end - 9.6) < 0.06)
    }

    @Test func shortGapsDoNotSplitButLongOnesDo() {
        let joined = RecordingSegmenter.segments(envelopeDB: envelope(seconds: 10, loud: [(1, 3), (3.3, 5)]),
                                                 hop: hop, duration: 10)
        #expect(joined.count == 1)
        let apart = RecordingSegmenter.segments(envelopeDB: envelope(seconds: 10, loud: [(1, 3), (3.8, 5)]),
                                                hop: hop, duration: 10)
        #expect(apart.count == 2)
    }

    @Test func dropsBlipsShorterThanAQuarterSecond() {
        let spans = RecordingSegmenter.segments(envelopeDB: envelope(seconds: 10, loud: [(2, 2.15), (5, 6)]),
                                                hop: hop, duration: 10)
        #expect(spans.count == 1)
        #expect(spans[0].start > 4)
    }

    @Test func splitsLongStretchesIntoEqualPieces() {
        let spans = RecordingSegmenter.segments(envelopeDB: envelope(seconds: 40, loud: [(0, 35)]),
                                                hop: hop, duration: 40)
        #expect(spans.count == 4)
        #expect(spans.allSatisfy { $0.length <= RecordingSegmenter.maximumSegmentSeconds + 1e-9 })
        for (a, b) in zip(spans, spans.dropFirst()) { #expect(abs(a.end - b.start) < 1e-9) }
    }

    @Test func silentRecordingHasNoSegments() {
        let env = [Float](repeating: -90, count: 400)
        #expect(RecordingSegmenter.segments(envelopeDB: env, hop: hop, duration: 20).isEmpty)
    }

    @Test func capsTheNumberOfSegmentsByEvenSampling() {
        let bursts = (0..<500).map { (Double($0) * 2, Double($0) * 2 + 1) }
        let spans = RecordingSegmenter.segments(envelopeDB: envelope(seconds: 1000, loud: bursts),
                                                hop: hop, duration: 1000)
        #expect(spans.count == RecordingSegmenter.maximumSegments)
        #expect(spans.last!.start > 900)
    }

    @Test func envelopeAndRangeDecodeOfARealFile() throws {
        let dir = TestSupport.tempDir()
        let url = dir.appendingPathComponent("long.wav")
        // 1 s tone, 2 s silence, 1 s tone at 22.05 kHz.
        try writeTestWav(url, seconds: 4, sampleRate: 22050) { t in
            (t < 1 || t >= 3) ? Float(sin(2 * .pi * 440 * t)) * 0.5 : 0
        }
        let env = try AudioDecoder.loudnessEnvelope(url: url)
        #expect(abs(env.duration - 4) < 0.01)
        #expect(abs(env.levelsDB.count - 80) <= 1)
        #expect(env.levelsDB[10] > -12 && env.levelsDB[10] < -8)      // 0.5 amplitude sine is about -9 dBFS
        #expect(env.levelsDB[40] < -80)
        let spans = RecordingSegmenter.segments(envelopeDB: env.levelsDB, hop: env.hop, duration: env.duration)
        #expect(spans.count == 2)

        let slice = try AudioDecoder.decode(url: url, start: 3, seconds: 10, sampleRate: 48000)
        #expect(abs(slice.count - 48000) < 200)                        // clipped at the end of the file
        #expect(slice.contains { abs($0) > 0.4 })
        let silent = try AudioDecoder.decode(url: url, start: 1.2, seconds: 1, sampleRate: 48000)
        #expect(silent.allSatisfy { abs($0) < 0.01 })
    }
}
