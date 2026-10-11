import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidLevelTests {
    private func tone(_ dir: URL, _ name: String, amplitude: Float, seconds: Double = 0.5) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try writeTestWav(url, seconds: seconds) { Float(sin($0 * 2 * .pi * 220)) * amplitude }
        return url
    }

    /// Peak and active loudness (dB) of a file as the module will play it.
    private func level(_ url: URL) throws -> (peak: Double, loudness: Double) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        return (20 * Double(log10(peak)), DescriptorAnalyzer.activeLoudness(samples, peak: peak))
    }

    private func send(_ sources: [SquidSource], to stick: URL) throws -> URL {
        try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "Levels", slots: sources.map { Optional($0) }), toVolume: stick)
    }

    @Test func samplesOfVeryDifferentLevelsArriveAtTheSameLoudness() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let quiet = try tone(dir, "quiet.wav", amplitude: 0.04)
        let loud = try tone(dir, "loud.wav", amplitude: 0.5)
        let bank = try send([SquidSource(file: quiet, name: "q", matchLevel: true), SquidSource(file: loud, name: "l", matchLevel: true)], to: stick)

        let q = try level(bank.appendingPathComponent("1/q.wav")), l = try level(bank.appendingPathComponent("2/l.wav"))
        #expect(abs(q.loudness - LoudnessMatch.targetDB) < 1, "quiet: \(q.loudness)")
        #expect(abs(l.loudness - LoudnessMatch.targetDB) < 1, "loud: \(l.loudness)")
        #expect(abs(q.loudness - l.loudness) < 0.5)
    }

    @Test func peaksStayBelowTheCeiling() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        // A few-sample click: a loud peak with a low average, which would clip if it were brought up to the target loudness.
        let url = dir.appendingPathComponent("click.wav")
        try writeTestWav(url, seconds: 0.5) { t in t > 0.1 && t < 0.1 + 5.0 / 44_100 ? 0.5 : 0 }
        let bank = try send([SquidSource(file: url, name: "c", matchLevel: true)], to: stick)
        let result = try level(bank.appendingPathComponent("1/c.wav"))
        #expect(result.peak <= LoudnessMatch.ceilingDB + 0.1, "peak \(result.peak)")
        #expect(result.peak > LoudnessMatch.ceilingDB - 1, "brought up as far as the ceiling allows")
    }

    @Test func levelsAreLeftAloneWhenMatchingIsOff() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let quiet = try tone(dir, "quiet.wav", amplitude: 0.02)
        let bank = try send([SquidSource(file: quiet, name: "q")], to: stick)
        let result = try level(bank.appendingPathComponent("1/q.wav"))
        #expect(abs(result.peak - 20 * Double(log10(Float(0.02)))) < 0.5)
    }

    @Test func aTrimmedSampleIsMatchedAsWhatIsLeftOfIt() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        // Loud first half, quiet second half; only the quiet half is sent.
        let url = dir.appendingPathComponent("two.wav")
        try writeTestWav(url, seconds: 2) { t in Float(sin(t * 2 * .pi * 220)) * (t < 1 ? 0.8 : 0.02) }
        let bank = try send([SquidSource(file: url, trim: SampleTrim(start: 1.1, end: 1.9), name: "t", matchLevel: true)], to: stick)
        let result = try level(bank.appendingPathComponent("1/t.wav"))
        #expect(abs(result.loudness - LoudnessMatch.targetDB) < 1.5, "loudness \(result.loudness)")
    }

    @Test func silenceStaysSilent() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let silent = try tone(dir, "silent.wav", amplitude: 0)
        let bank = try send([SquidSource(file: silent, name: "s", matchLevel: true)], to: stick)
        let file = try AVAudioFile(forReading: bank.appendingPathComponent("1/s.wav"))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        #expect(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)).allSatisfy { $0 == 0 })
    }
}
