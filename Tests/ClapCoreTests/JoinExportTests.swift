import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct JoinExportTests {
    @Test func joinsAudioWithSilentGapsAndNewNamedRegions() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("Kick.wav"), second = dir.appendingPathComponent("Snare.wav")
        try writeTestWav(first, seconds: 0.1) { _ in 0.25 }
        try writeTestWav(second, seconds: 0.1) { _ in 0.5 }
        try WavCueWriter.write(cues: [FileCue(frame: 200, label: "Old")], to: first, keepBackup: false)
        let originals = try [first, second].map { try Data(contentsOf: $0) }
        let output = try JoinExporter.export([JoinSource(url: first), JoinSource(url: second)],
                                             settings: JoinSettings(), to: dir.appendingPathComponent("out"))
        let file = try AVAudioFile(forReading: #require(output.first))
        #expect(file.length == 19_845, "The file holds two sounds and exactly one quarter-second of silence.")
        #expect(file.processingFormat.sampleRate == 44_100 && file.processingFormat.channelCount == 1)
        let audio = try TrimRender.read(url: output[0])
        let channel = try #require(audio.floatChannelData?[0])
        #expect(abs(channel[1_000] - 0.25) < 0.0001 && abs(channel[16_000] - 0.5) < 0.0001)
        #expect((4_410..<15_435).allSatisfy { channel[$0] == 0 }, "Only silence is inserted between the unedited sounds.")
        #expect(CueFileReader.read(url: output[0]) == [
            FileCue(frame: 0, label: "Kick"), FileCue(frame: 15_435, label: "Snare"),
        ], "Old source cues are replaced by one named start marker per sound.")
        #expect(JoinedCueWriter.regionLengths(in: try Data(contentsOf: output[0])) == [4_410, 4_410],
                "WAV region lengths mark exact sound ends without including the gap.")
        #expect(try [first, second].map { try Data(contentsOf: $0) } == originals)
    }

    @Test func trimsAndSpeedEditsApplyBeforeJoining() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("sound.wav")
        try writeTestWav(source, seconds: 0.2) { _ in 0.5 }
        let trim = SampleTrim(start: 0.05, end: 0.15, edit: SampleEdit(gainDB: -6, speedSemitones: 12))
        let outputs = try JoinExporter.export([JoinSource(url: source, trim: trim)],
                                               settings: JoinSettings(maxSeconds: 0.06), to: dir.appendingPathComponent("out"))
        let audio = try TrimRender.read(url: outputs[0])
        #expect(abs(Int(audio.frameLength) - 2_205) <= 1, "The trimmed tenth-second sound plays twice as fast.")
        #expect(abs(audio.floatChannelData![0][1_000] - 0.25) < 0.002)
    }

    @Test func mixedSampleRatesAreConvertedAndLimitsUseWrittenFrames() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("a.wav"), second = dir.appendingPathComponent("b.wav")
        try writeTestWav(first, seconds: 0.1) { _ in 0.25 }
        try writeTestWav(second, seconds: 0.1, sampleRate: 48_000) { _ in 0.5 }
        let outputs = try JoinExporter.export([JoinSource(url: first), JoinSource(url: second)],
                                               settings: JoinSettings(maxSeconds: 0.15, silenceSeconds: 0), to: dir.appendingPathComponent("out"))
        #expect(outputs.count == 2)
        for output in outputs {
            let audio = try AVAudioFile(forReading: output)
            #expect(abs(audio.length - 4_410) <= 1)
            #expect(audio.processingFormat.sampleRate == 44_100)
        }
    }

    @Test func stereoKeepsBothChannelsAndMonoCanBeChosen() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("stereo.wav")
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        for index in 0..<4_410 {
            buffer.floatChannelData![0][index] = 0.25
            buffer.floatChannelData![1][index] = 0.5
        }
        do {
            let file = try AVAudioFile(forWriting: source, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            ])
            try file.write(from: buffer)
        }
        let stereo = try JoinExporter.export([JoinSource(url: source)], settings: JoinSettings(mono: false),
                                             to: dir.appendingPathComponent("stereo"))
        let audio = try TrimRender.read(url: stereo[0])
        #expect(audio.format.channelCount == 2)
        #expect(abs(audio.floatChannelData![0][100] - 0.25) < 0.0001)
        #expect(abs(audio.floatChannelData![1][100] - 0.5) < 0.0001)
        let mono = try JoinExporter.export([JoinSource(url: source)], settings: JoinSettings(),
                                           to: dir.appendingPathComponent("mono"))
        #expect(try AVAudioFile(forReading: mono[0]).processingFormat.channelCount == 1)
    }

    @Test func countLimitAndNameClashesKeepExistingFilesUntouched() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Joined 1.wav")
        try writeTestWav(source, seconds: 0.1) { _ in 0.25 }
        let original = try Data(contentsOf: source)
        let outputs = try JoinExporter.export([JoinSource(url: source), JoinSource(url: source)],
                                               settings: JoinSettings(maxCuePoints: 1), to: dir)
        #expect(outputs.count == 2 && !outputs.contains(source))
        #expect(try Data(contentsOf: source) == original, "Even an output name matching a source never replaces it.")
        #expect(outputs.allSatisfy { CueFileReader.read(url: $0).count == 1 })
    }

    @Test func aMissingOrOversizedSourcePublishesNothing() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("good.wav"), folder = dir.appendingPathComponent("out")
        try writeTestWav(source, seconds: 0.2) { _ in 0.25 }
        #expect(throws: (any Error).self) {
            try JoinExporter.export([JoinSource(url: source), JoinSource(url: dir.appendingPathComponent("missing.wav"))],
                                     settings: JoinSettings(), to: folder)
        }
        #expect(throws: JoinError.self) {
            try JoinExporter.export([JoinSource(url: source)], settings: JoinSettings(maxSeconds: 0.1), to: folder)
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty != false,
                "An unsuccessful batch leaves no joined files or temporary files behind.")
    }

    @Test func cancellationDoesNotPublishFiles() async throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try JoinExporter.export([], settings: JoinSettings(), to: dir)
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled join must stop before publishing any files.")
        } catch is CancellationError {}
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}
