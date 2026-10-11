import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidNormalizerTests {
    private func tone(_ dir: URL, _ name: String, amplitude: Float) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try writeTestWav(url, seconds: 0.5) { Float(sin($0 * 2 * .pi * 220)) * amplitude }
        return url
    }

    private func loudness(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        return DescriptorAnalyzer.activeLoudness(samples, peak: samples.reduce(Float(0)) { max($0, abs($1)) })
    }

    /// A stick with an unmatched quiet and loud sample in a bank and a loud one in the Pool.
    private func makeStick() throws -> (stick: URL, bank: URL, pool: URL) {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let quiet = try tone(dir, "quiet.wav", amplitude: 0.05), loud = try tone(dir, "loud.wav", amplitude: 0.7)
        let bank = try SquidExporter.export(SquidBankRequest(set: "Kit", number: 1, name: "K", slots: [
            SquidSource(file: quiet, name: "q", category: "Kick"), SquidSource(file: loud, name: "l")]), toVolume: stick)
        let pool = try SquidExporter.exportToPool([SquidSource(file: loud, name: "p")], toVolume: stick)[0]
        return (stick, bank, pool)
    }

    @Test func everySampleOnTheStickEndsUpAtTheCommonLoudness() throws {
        let (stick, bank, pool) = try makeStick()
        let report = SquidNormalizer.normalizeAll(volume: stick)
        #expect(report.adjusted == 3 && report.alreadyMatched == 0 && report.skipped.isEmpty && report.failed.isEmpty)
        for file in [bank.appendingPathComponent("1/q.wav"), bank.appendingPathComponent("2/l.wav"), pool] {
            let level = try loudness(file)
            #expect(abs(level - LoudnessMatch.targetDB) < 1.5, "\(file.lastPathComponent): \(level)")
        }
    }

    @Test func runningItAgainChangesNothing() throws {
        let (stick, bank, _) = try makeStick()
        SquidNormalizer.normalizeAll(volume: stick)
        let file = bank.appendingPathComponent("1/q.wav")
        let before = try Data(contentsOf: file)
        let again = SquidNormalizer.normalizeAll(volume: stick)
        #expect(again.adjusted == 0 && again.alreadyMatched == 3)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func onlyTheAudioChanges() throws {
        let (stick, bank, _) = try makeStick()
        let file = bank.appendingPathComponent("1/q.wav")
        let before = try Data(contentsOf: file)
        #expect(WavInfo.genre(of: file) == "Kick")
        SquidNormalizer.normalizeAll(volume: stick)
        let after = try Data(contentsOf: file)
        #expect(after.count == before.count && after != before)
        #expect(WavInfo.genre(of: file) == "Kick", "the category tag survives")
        let chunk = try #require(WavChunks.parse(before).first { $0.id == "data" })
        #expect(after[..<chunk.dataStart] == before[..<chunk.dataStart])
        #expect(after[(chunk.dataStart + chunk.size)...] == before[(chunk.dataStart + chunk.size)...])
        let left = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(left == ["q.wav"], "no temporary copies are left behind")
    }

    @Test func otherFormatsAndHiddenFilesAreLeftAlone() throws {
        let (stick, _, pool) = try makeStick()
        let dir = TestSupport.tempDir()
        let deep = try tone(dir, "deep.wav", amplitude: 0.3)
        let folder = pool.deletingLastPathComponent()
        try TrimExporter.write(source: deep, trim: nil, format: ExportFormat(bitDepth: .int24), to: folder.appendingPathComponent("deep24.wav"))
        let hidden = folder.appendingPathComponent("._p.wav")
        try Data("not audio".utf8).write(to: hidden)
        let before24 = try Data(contentsOf: folder.appendingPathComponent("deep24.wav"))

        let report = SquidNormalizer.normalizeAll(volume: stick)
        #expect(report.skipped == ["deep24.wav"] && report.failed.isEmpty)
        #expect(try Data(contentsOf: folder.appendingPathComponent("deep24.wav")) == before24)
        #expect(try Data(contentsOf: hidden) == Data("not audio".utf8))
    }

    @Test func silenceAndEmptyStickAreFine() throws {
        let stick = TestSupport.tempDir()
        #expect(SquidNormalizer.normalizeAll(volume: stick) == SquidNormalizeReport())
        let silent = try tone(TestSupport.tempDir(), "s.wav", amplitude: 0)
        let pool = try SquidExporter.exportToPool([SquidSource(file: silent, name: "s")], toVolume: stick)[0]
        let before = try Data(contentsOf: pool)
        let report = SquidNormalizer.normalizeAll(volume: stick)
        #expect(report.alreadyMatched == 1 && report.adjusted == 0)
        #expect(try Data(contentsOf: pool) == before)
    }
}
