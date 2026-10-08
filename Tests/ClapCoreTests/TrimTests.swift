import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SampleTrimTests {
    @Test func clampingKeepsTheTrimInsideTheFile() {
        let t = SampleTrim(start: -1, end: 50, fadeOut: 100).clamped(toDuration: 10)
        #expect(t == SampleTrim(start: 0, end: 10, fadeOut: 10))
        #expect(SampleTrim(start: 3, end: 3.005).clamped(toDuration: 10) == nil, "too short to keep")
        #expect(SampleTrim(start: 12, end: 14).clamped(toDuration: 10) == nil, "past the end")
        #expect(SampleTrim(start: 0, end: 1).clamped(toDuration: 0) == nil)
    }

    @Test func wholeFileDetection() {
        #expect(SampleTrim(start: 0, end: 10).coversWholeFile(duration: 10))
        #expect(!SampleTrim(start: 0, end: 10, fadeOut: 1).coversWholeFile(duration: 10))
        #expect(!SampleTrim(start: 1, end: 10).coversWholeFile(duration: 10))
    }

    @Test func declickIsTheMinimumFade() {
        #expect(SampleTrim(start: 0, end: 1).effectiveFadeOut == SampleTrim.declick)
        #expect(SampleTrim(start: 0, end: 1, fadeOut: 0.5).effectiveFadeOut == 0.5)
    }
}

@Suite struct TrimRenderTests {
    private func ramp(_ url: URL, seconds: Double, rate: Double = 8000) throws {
        // value encodes the time: 0.1 per second, so frame positions can be checked from the samples
        try writeTestWav(url, seconds: seconds, sampleRate: rate) { Float($0 * 0.05) }
    }

    @Test func readsOnlyTheRequestedRegion() throws {
        let url = TestSupport.tempDir().appendingPathComponent("long.wav")
        try ramp(url, seconds: 10)
        let b = try TrimRender.read(url: url, start: 2, end: 4)
        #expect(abs(Double(b.frameLength) - 16000) <= 1)
        let first = b.floatChannelData![0][100]
        #expect(abs(first - Float((2 + 100.0 / 8000) * 0.05)) < 0.002, "starts at the 2 s mark")
    }

    @Test func fadesReachSilenceAtTheEdges() throws {
        let url = TestSupport.tempDir().appendingPathComponent("loud.wav")
        try writeTestWav(url, seconds: 1, sampleRate: 8000) { _ in 0.5 }
        let b = try TrimRender.read(url: url, fadeIn: 0.1, fadeOut: 0.2)
        let d = b.floatChannelData![0], n = Int(b.frameLength)
        #expect(d[0] == 0 && d[n - 1] == 0)
        #expect(abs(d[400] - 0.25) < 0.01, "halfway through the 100 ms fade-in")
        #expect(abs(d[n / 2] - 0.5) < 0.001, "untouched in the middle")
    }

    @Test func fadesNeverOverlapOnShortBuffers() throws {
        let url = TestSupport.tempDir().appendingPathComponent("short.wav")
        try writeTestWav(url, seconds: 0.1, sampleRate: 8000) { _ in 0.5 }
        let b = try TrimRender.read(url: url, fadeIn: 5, fadeOut: 5)
        #expect(b.floatChannelData![0].pointee.isFinite)
    }

    @Test func maxSecondsLimitsWhatIsRead() throws {
        let url = TestSupport.tempDir().appendingPathComponent("cap.wav")
        try ramp(url, seconds: 5)
        let b = try TrimRender.read(url: url, start: 1, maxSeconds: 0.5)
        #expect(abs(Double(b.frameLength) - 4000) <= 1)
    }

    @Test func peaksCoverTheWholeFile() throws {
        let url = TestSupport.tempDir().appendingPathComponent("peaks.wav")
        // silence, then a loud second half
        try writeTestWav(url, seconds: 4, sampleRate: 8000) { $0 < 2 ? 0 : 0.8 }
        let peaks = try WaveformPeaks.compute(url: url, bins: 10)
        #expect(peaks.count == 20)
        #expect(peaks[1] == 0 && peaks[2 * 4 + 1] == 0, "first half silent")
        #expect(peaks[2 * 9 + 1] > 0.7, "second half loud")
    }
}

@Suite struct TrimStoreTests {
    @Test func trimsPersistAndClear() throws {
        let (store, dir) = try TestSupport.makeStore()
        try store.setTrim(SampleTrim(start: 1.5, end: 4, fadeOut: 0.25), sampleID: 7)
        try store.setTrim(SampleTrim(start: 2, end: 3), sampleID: 7)       // update in place
        try store.setTrim(SampleTrim(start: 0, end: 1), sampleID: 8)
        #expect(store.trims() == [7: SampleTrim(start: 2, end: 3), 8: SampleTrim(start: 0, end: 1)])
        let reopened = try LibraryStore(path: dir.appendingPathComponent("lib.sqlite").path)
        #expect(reopened.trims().count == 2, "survives a restart")
        try store.setTrim(nil, sampleID: 7)
        #expect(store.trims().keys.sorted() == [8])
    }
}
