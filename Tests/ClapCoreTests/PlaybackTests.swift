import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct PlaybackTests {
    @Test func decodesToEngineFormatAndCaches() throws {
        let dir = TestSupport.tempDir()
        let url = dir.appendingPathComponent("tone.wav")
        try writeTestWav(url, seconds: 0.25, sampleRate: 22050) { Float(sin(2 * .pi * 440 * $0)) * 0.5 }
        let cache = AudioBufferCache(sampleRate: 48000)
        #expect(cache.cached(url) == nil)
        let buffer = try cache.buffer(for: url)
        #expect(buffer.format.channelCount == 2 && buffer.format.sampleRate == 48000)
        #expect(abs(Int(buffer.frameLength) - 12000) < 200)
        #expect(cache.cached(url) === buffer)
    }

    @Test func cacheEvictsLeastRecentlyUsed() throws {
        let dir = TestSupport.tempDir()
        var urls: [URL] = []
        for i in 0..<3 {
            let u = dir.appendingPathComponent("s\(i).wav")
            try writeTestWav(u, seconds: 0.5, sampleRate: 48000) { _ in 0.1 }
            urls.append(u)
        }
        // Capacity fits roughly two half-second stereo buffers.
        let cache = AudioBufferCache(sampleRate: 48000, capacityBytes: 2 * 192_000 + 1_000)
        _ = try cache.buffer(for: urls[0]); _ = try cache.buffer(for: urls[1])
        _ = cache.cached(urls[0])                       // touch 0 so 1 is the oldest
        _ = try cache.buffer(for: urls[2])
        #expect(cache.cached(urls[1]) == nil)
        #expect(cache.cached(urls[2]) != nil)
    }

    @Test func peaksCaptureEnvelope() throws {
        let url = TestSupport.tempDir().appendingPathComponent("p.wav")
        try writeTestWav(url, seconds: 1, sampleRate: 48000) { $0 < 0.5 ? 0.8 : 0.1 }
        let buffer = try AudioBufferCache(sampleRate: 48000).buffer(for: url)
        let peaks = AudioBufferCache.peaks(of: buffer, bins: 10)
        #expect(peaks.count == 20)
        #expect(peaks[1] > 0.7 && peaks[19] < 0.2)
    }

    @Test func sliceStartsAtRequestedFrame() throws {
        let url = TestSupport.tempDir().appendingPathComponent("s.wav")
        try writeTestWav(url, seconds: 1, sampleRate: 48000) { $0 < 0.5 ? 0.0 : 0.5 }
        let buffer = try AudioBufferCache(sampleRate: 48000).buffer(for: url)
        let slice = try #require(SamplePlayer.slice(buffer, from: 24000 + 100))
        #expect(Int(slice.frameLength) == Int(buffer.frameLength) - 24100)
        #expect(abs(slice.floatChannelData![0][0] - 0.5) < 0.01)
    }

    @Test func playbackStatePlayhead() {
        let now = Date()
        let s = PlaybackState(sampleID: 1, startSeconds: 0.5, startedAt: now, duration: 2)
        #expect(abs((s.playhead(at: now.addingTimeInterval(0.25)) ?? 0) - 0.75) < 1e-6)
        #expect(s.playhead(at: now.addingTimeInterval(5)) == nil)
        #expect(PlaybackState().playhead() == nil)
    }
}
