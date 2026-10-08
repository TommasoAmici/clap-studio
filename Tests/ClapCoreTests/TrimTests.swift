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

@Suite struct TrimExporterTests {
    private func channelsAndRate(_ url: URL) throws -> (frames: Int64, channels: Int, rate: Double, depth: Int?) {
        let f = try AVAudioFile(forReading: url)
        return (f.length, Int(f.fileFormat.channelCount), f.fileFormat.sampleRate, f.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int)
    }

    @Test func exportsTheTrimmedRegionAndLeavesTheOriginalAlone() throws {
        let dir = TestSupport.tempDir()
        let src = dir.appendingPathComponent("rumble.wav")
        try writeTestWav(src, seconds: 10, sampleRate: 8000) { _ in 0.4 }
        let before = try Data(contentsOf: src)
        let out = dir.appendingPathComponent("out/trim.wav")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TrimExporter.write(source: src, trim: SampleTrim(start: 2, end: 3.5), format: ExportFormat(), to: out)
        let info = try channelsAndRate(out)
        #expect(abs(Double(info.frames) - 12000) <= 1)
        #expect(info.rate == 8000 && info.depth == 16, "keeps the source format")
        #expect(try Data(contentsOf: src) == before, "the original is untouched")
        let b = try TrimRender.read(url: out)
        #expect(b.floatChannelData![0][0] == 0, "starts from silence (declick)")
        #expect(abs(b.floatChannelData![0][6000] - 0.4) < 0.01)
    }

    @Test func convertsFormatForASampler() throws {
        let dir = TestSupport.tempDir()
        let src = dir.appendingPathComponent("a.wav")
        try writeTestWav(src, seconds: 2, sampleRate: 44100) { Float(sin(2 * .pi * 100 * $0)) * 0.5 }
        let out = dir.appendingPathComponent("b.wav")
        try TrimExporter.write(source: src, trim: SampleTrim(start: 0.5, end: 1.5),
                               format: ExportFormat(bitDepth: .int24, mono: true, sampleRate: 48000), to: out)
        let info = try channelsAndRate(out)
        #expect(info.rate == 48000 && info.channels == 1 && info.depth == 24)
        #expect(abs(Double(info.frames) - 48000) < 200, "one second at the new rate, got \(info.frames)")
    }

    @Test func exportCopiesPlainFilesRendersTrimmedOnesAndNeverOverwrites() throws {
        let dir = TestSupport.tempDir()
        let a = dir.appendingPathComponent("a.wav"), b = dir.appendingPathComponent("b.wav")
        try writeTestWav(a, seconds: 1, sampleRate: 8000) { _ in 0.2 }
        try writeTestWav(b, seconds: 4, sampleRate: 8000) { _ in 0.2 }
        let dest = dir.appendingPathComponent("dest")
        let items = [TrimExporter.Item(source: a, trim: nil, fileName: "a.wav"),
                     TrimExporter.Item(source: b, trim: SampleTrim(start: 1, end: 2), fileName: "b.aiff")]
        let first = TrimExporter.export(items, format: ExportFormat(), to: dest)
        let second = TrimExporter.export(items, format: ExportFormat(), to: dest)
        #expect(first.failures.isEmpty && second.failures.isEmpty)
        #expect(Set(first.copied.map(\.lastPathComponent)) == ["a.wav", "b.wav"], "trimmed files are written as .wav")
        #expect(Set(second.copied.map(\.lastPathComponent)) == ["a 2.wav", "b 2.wav"])
        #expect(try channelsAndRate(dest.appendingPathComponent("b.wav")).frames == 8000)
        #expect(try channelsAndRate(dest.appendingPathComponent("a.wav")).frames == 8000, "untrimmed copy is byte for byte")
    }

    @Test func unreadableSourcesAreReportedNotThrown() {
        let dir = TestSupport.tempDir()
        let r = TrimExporter.export([.init(source: dir.appendingPathComponent("missing.wav"), trim: SampleTrim(start: 0, end: 1), fileName: "x.wav")],
                                    format: ExportFormat(), to: dir.appendingPathComponent("o"))
        #expect(r.copied.isEmpty && r.failures.count == 1)
    }
}
