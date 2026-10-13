import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SampleEditTests {
    private let rate = 16000.0

    private func tone(_ hz: Double, seconds: Double = 1, amplitude: Float = 0.5) throws -> (URL, AVAudioPCMBuffer) {
        let url = TestSupport.tempDir().appendingPathComponent("tone.wav")
        try writeTestWav(url, seconds: seconds, sampleRate: rate) { Float(sin(2 * .pi * hz * $0)) * amplitude }
        return (url, try TrimRender.read(url: url))
    }

    private func samples(_ b: AVAudioPCMBuffer) -> [Float] { Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength))) }

    private func rms(_ x: ArraySlice<Float>) -> Double { sqrt(x.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(1, x.count))) }

    /// Cycles per second, from upward zero crossings.
    private func frequency(_ b: AVAudioPCMBuffer) -> Double {
        let x = samples(b)
        var crossings = 0
        for i in 1..<x.count where x[i - 1] < 0 && x[i] >= 0 { crossings += 1 }
        return Double(crossings) / (Double(x.count) / b.format.sampleRate)
    }

    @Test func noEditChangesNothing() throws {
        let (_, b) = try tone(440)
        #expect(SampleEdit().isNeutral && EditRender.apply(b, edit: SampleEdit()) === b)
        #expect(SampleEdit(gainDB: 0.01).clamped().isNeutral, "a hair's breadth is no edit")
        #expect(SampleEdit(gainDB: 99, speedSemitones: -99).clamped() == SampleEdit(gainDB: 12, speedSemitones: -24))
    }

    @Test func reversingRunsTheSoundBackwards() throws {
        let url = TestSupport.tempDir().appendingPathComponent("ramp.wav")
        try writeTestWav(url, seconds: 1, sampleRate: rate) { Float($0 * 0.5) }
        let b = try TrimRender.read(url: url)
        let r = samples(EditRender.apply(b, edit: SampleEdit(reverse: true)))
        let x = samples(b)
        #expect(r.count == x.count && r.first == x.last && r.last == x.first)
        #expect(r[100] == x[x.count - 101])
    }

    @Test func volumeIsInDecibelsAndClipsAtFullScale() throws {
        let (_, b) = try tone(200, amplitude: 0.25)
        let louder = samples(EditRender.apply(b, edit: SampleEdit(gainDB: 6.0206)))
        #expect(abs(rms(louder[...]) / rms(samples(b)[...]) - 2) < 0.01, "+6 dB doubles the level")
        let (_, loud) = try tone(200, amplitude: 0.5)
        let clipped = samples(EditRender.apply(loud, edit: SampleEdit(gainDB: 12)))
        #expect(clipped.max()! <= 1 && clipped.min()! >= -1 && clipped.max()! == 1)
        let quieter = samples(EditRender.apply(b, edit: SampleEdit(gainDB: -20)))
        #expect(abs(rms(quieter[...]) / rms(samples(b)[...]) - 0.1) < 0.005)
    }

    @Test func speedMovesPitchAndLengthTogether() throws {
        let (_, b) = try tone(440)
        let up = EditRender.apply(b, edit: SampleEdit(speedSemitones: 12))
        #expect(abs(Double(up.frameLength) - Double(b.frameLength) / 2) <= 1, "an octave up is half as long")
        #expect(abs(frequency(up) - 880) < 6)
        let down = EditRender.apply(b, edit: SampleEdit(speedSemitones: -12))
        #expect(abs(Double(down.frameLength) - Double(b.frameLength) * 2) <= 2)
        #expect(abs(frequency(down) - 220) < 4)
        #expect(abs(SampleEdit(speedSemitones: 12).lengthFactor - 0.5) < 1e-9)
    }

    @Test func fasterPlaybackDoesNotFoldHighFrequenciesBackDown() throws {
        let (_, b) = try tone(6000)
        let up = samples(EditRender.apply(b, edit: SampleEdit(speedSemitones: 12)))
        // 12 kHz does not fit in a 16 kHz recording; it must be gone, not mirrored to 4 kHz
        #expect(rms(up[200...]) < 0.05)
    }

    @Test func filtersRemoveWhatIsBeyondTheCutoff() throws {
        let (_, low) = try tone(200), (_, high) = try tone(4000)
        func level(_ b: AVAudioPCMBuffer, _ edit: SampleEdit) -> Double { rms(samples(EditRender.apply(b, edit: edit))[2000...]) }
        let reference = rms(samples(low)[2000...])
        #expect(level(low, SampleEdit(lowPassHz: 1000)) > reference * 0.9, "below the cutoff passes")
        #expect(level(high, SampleEdit(lowPassHz: 1000)) < reference * 0.05, "above it is removed")
        #expect(level(high, SampleEdit(highPassHz: 1000)) > reference * 0.9)
        #expect(level(low, SampleEdit(highPassHz: 1000)) < reference * 0.05)
        #expect(level(high, SampleEdit(lowPassHz: 9000, highPassHz: 100)) > reference * 0.9, "a band in between passes")
    }

    @Test func stereoChannelsAreEditedAlike() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
        b.frameLength = 100
        for i in 0..<100 { b.floatChannelData![0][i] = Float(i) / 200; b.floatChannelData![1][i] = -Float(i) / 200 }
        let r = EditRender.apply(b, edit: SampleEdit(reverse: true))
        #expect(r.floatChannelData![0][0] == 99.0 / 200 && r.floatChannelData![1][0] == -99.0 / 200)
    }

    // MARK: with the trim

    @Test func aTrimCarriesItsEditAndKeepsItWhenClamped() {
        let trim = SampleTrim(start: 1, end: 20, edit: SampleEdit(reverse: true, gainDB: 40))
        let fitted = trim.clamped(toDuration: 10)
        #expect(fitted?.edit == SampleEdit(reverse: true, gainDB: 12) && fitted?.end == 10)
        #expect(SampleTrim(start: 0, end: 10, edit: SampleEdit(reverse: true)).coversWholeFile(duration: 10), "an edit alone cuts nothing")
    }

    @Test func fadesComeAfterTheEditSoAReversedSoundStillFadesIn() throws {
        let url = TestSupport.tempDir().appendingPathComponent("loud.wav")
        try writeTestWav(url, seconds: 1, sampleRate: rate) { $0 < 0.5 ? 0.9 : 0.1 }
        let b = try TrimRender.read(url: url, fadeIn: 0.01, fadeOut: 0.01, edit: SampleEdit(reverse: true))
        let x = samples(b)
        #expect(x[0] == 0 && x[x.count - 1] == 0)
        #expect(abs(x[1000] - 0.1) < 0.01 && abs(x[x.count - 1000] - 0.9) < 0.01, "the quiet half now comes first")
    }

    @Test func aWholeFileEditIsRenderedWhenExportingAndTheOriginalIsUntouched() throws {
        let dir = TestSupport.tempDir()
        let src = dir.appendingPathComponent("ramp.wav")
        try writeTestWav(src, seconds: 1, sampleRate: rate) { Float($0 * 0.5) }
        let before = try Data(contentsOf: src)
        let out = dir.appendingPathComponent("out.wav")
        try TrimExporter.write(source: src, trim: SampleTrim(start: 0, end: 1, edit: SampleEdit(reverse: true, gainDB: -6.0206)),
                               format: ExportFormat(), to: out)
        let b = try TrimRender.read(url: out)
        let x = samples(b)
        #expect(abs(x[200] - 0.5 * 0.5 * Float(1 - 200.0 / rate)) < 0.01, "reversed and half as loud")
        #expect(x.first! < 0.01 && x[x.count / 2] > 0, "declick at the edges")
        #expect(try Data(contentsOf: src) == before)
    }

    @Test func editsAreStoredWithTheTrim() throws {
        let (store, dir) = try TestSupport.makeStore()
        let root = try store.addRoot(path: dir.path)
        _ = try store.sync(rootID: root.id, scanned: [ScannedFile(relPath: "a.wav", size: 1, mtime: 1)]) { _ in nil }
        let id = store.loadSamples()[0].id
        let trim = SampleTrim(start: 0.5, end: 2, fadeOut: 0.25,
                              edit: SampleEdit(reverse: true, gainDB: -3.5, speedSemitones: 5, lowPassHz: 4000, highPassHz: 80))
        try store.setTrim(trim, sampleID: id)
        #expect(store.trims()[id] == trim)
        try store.setTrim(SampleTrim(start: 0, end: 1, edit: SampleEdit(gainDB: 3)), sampleID: id)
        #expect(store.trims()[id]?.edit == SampleEdit(gainDB: 3), "the filters are off again")
        try store.setTrim(nil, sampleID: id)
        #expect(store.trims()[id] == nil)
    }

    @Test func aSummaryNamesWhatChanged() {
        #expect(SampleEdit().summary.isEmpty)
        #expect(SampleEdit(reverse: true, gainDB: 3, speedSemitones: -2, lowPassHz: 4000).summary == "reversed, -2.0 st, +3.0 dB, low-pass 4 kHz")
        #expect(SampleEdit(highPassHz: 80).summary == "high-pass 80 Hz")
    }
}
