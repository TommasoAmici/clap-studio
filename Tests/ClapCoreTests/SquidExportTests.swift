import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidExportTests {
    private func makeSource(_ dir: URL, _ name: String, seconds: Double, rate: Double = 48_000, level: Float = 0.5) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try writeTestWav(url, seconds: seconds, sampleRate: rate) { _ in level }
        return url
    }

    private func info(_ url: URL) throws -> (frames: Int64, rate: Double, channels: Int, depth: Int?) {
        let f = try AVAudioFile(forReading: url)
        return (f.length, f.fileFormat.sampleRate, Int(f.fileFormat.channelCount), f.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int)
    }

    @Test func writesABankInTheSquidLayout() throws {
        let dir = TestSupport.tempDir()
        let stick = TestSupport.tempDir()
        let kick = try makeSource(dir, "kick.wav", seconds: 0.5)
        let long = try makeSource(dir, "rumble.wav", seconds: 30)
        let request = SquidBankRequest(set: nil, number: 3, name: "Rumble Kit Long", slots: [
            SquidSource(file: kick, name: "Kick 808"), nil, SquidSource(file: long, trim: SampleTrim(start: 1, end: 25), name: "Big/Rumble")])
        let bank = try SquidExporter.export(request, toVolume: stick)

        #expect(bank.path == stick.appendingPathComponent("ALM022/Bank 3").path)
        #expect(try String(contentsOf: bank.appendingPathComponent("info.txt"), encoding: .utf8) == "Rumble Kit Long\n", "kept as typed, even past 8 characters")
        let k = try info(bank.appendingPathComponent("1/Kick 808.wav"))
        #expect(k.rate == 44_100 && k.channels == 1 && k.depth == 16, "the module's native format")
        #expect(abs(Double(k.frames) - 22_050) < 100)
        let r = try info(bank.appendingPathComponent("3/BigRumble.wav"))
        #expect(abs(Double(r.frames) - 11 * 44_100) < 100, "cut at 11 seconds")
        #expect(!FileManager.default.fileExists(atPath: bank.appendingPathComponent("2").path), "an empty channel has no folder")
        // The sources are untouched.
        #expect(try info(long).frames == 30 * 48_000)
    }

    @Test func aDriveIsForTheModuleWhenItHoldsAnALM022Folder() throws {
        let fm = FileManager.default
        let plain = TestSupport.tempDir(), module = TestSupport.tempDir(), fileOnly = TestSupport.tempDir()
        try fm.createDirectory(at: module.appendingPathComponent("ALM022"), withIntermediateDirectories: true)
        try Data().write(to: fileOnly.appendingPathComponent("ALM022"))
        #expect(!SquidStick.isForModule(volume: plain))
        #expect(SquidStick.isForModule(volume: module))
        #expect(!SquidStick.isForModule(volume: fileOnly), "a file with that name is not the folder")
    }

    @Test func readingBackWhatWasWritten() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav", seconds: 0.2)
        try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "One", slots: [SquidSource(file: a, name: "a")]), toVolume: stick)
        try SquidExporter.export(SquidBankRequest(set: "Loops", number: 5, name: "Five", slots: [SquidSource(file: a, name: "a"), SquidSource(file: a, name: "b")]), toVolume: stick)
        try FileManager.default.createDirectory(at: stick.appendingPathComponent("ALM022/Pool"), withIntermediateDirectories: true)

        let contents = SquidStick.read(volume: stick)
        #expect(contents.hasSquidFolder && contents.hasPool)
        #expect(contents.sets.map(\.title) == ["Default", "Loops"])
        #expect(contents.set(named: nil)?.banks.map(\.name) == ["One"])
        #expect(contents.set(named: "Loops")?.banks.first?.filledSlots == 2)
        #expect(contents.set(named: "Loops")?.banks.first?.freeSlots == 6, "8 slots minus the 2 that are filled")
        #expect(SquidBank(set: nil, number: 1, name: "", filled: Set(1...8)).freeSlots == 0)
        #expect(contents.freeBankNumbers(inSet: nil).first == 2)
        #expect(contents.freeBankNumbers(inSet: "Loops").first == 1)
        #expect(SquidStick.read(volume: TestSupport.tempDir()).hasSquidFolder == false)
    }

    @Test func existingBanksAreProtectedUnlessReplacing() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav", seconds: 0.2)
        let request = SquidBankRequest(set: nil, number: 2, name: "A", slots: [SquidSource(file: a, name: "a")])
        try SquidExporter.export(request, toVolume: stick)
        #expect(throws: SquidExportError.bankExists("Bank 2")) { try SquidExporter.export(request, toVolume: stick) }
        var replace = request; replace.replaceExisting = true; replace.slots = [nil, SquidSource(file: a, name: "b")]
        try SquidExporter.export(replace, toVolume: stick)
        let bank = stick.appendingPathComponent("ALM022/Bank 2")
        #expect(FileManager.default.fileExists(atPath: bank.appendingPathComponent("2/b.wav").path))
        #expect(!FileManager.default.fileExists(atPath: bank.appendingPathComponent("1").path), "the old contents are gone, not merged")
    }

    @Test func badRequestsAreRejectedBeforeTouchingTheStick() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav", seconds: 0.2)
        let src = SquidSource(file: a, name: "a")
        #expect(throws: (any Error).self) { try SquidExporter.export(SquidBankRequest(set: nil, number: 0, name: "x", slots: [src]), toVolume: stick) }
        #expect(throws: (any Error).self) { try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "x", slots: [nil, nil]), toVolume: stick) }
        #expect(throws: (any Error).self) { try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "x", slots: Array(repeating: src, count: 9)), toVolume: stick) }
        let missing = SquidSource(file: dir.appendingPathComponent("gone.wav"), name: "g")
        #expect(throws: (any Error).self) { try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "x", slots: [missing]), toVolume: stick) }
        #expect(!FileManager.default.fileExists(atPath: stick.appendingPathComponent("ALM022").path), "nothing was created")
    }

    @Test func stickLimitsAreEnforced() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav", seconds: 0.1)
        for i in 1...SquidLayout.maxSets {
            try FileManager.default.createDirectory(at: stick.appendingPathComponent("ALM022/Set S\(i)"), withIntermediateDirectories: true)
        }
        let request = SquidBankRequest(set: "Extra", number: 1, name: "x", slots: [SquidSource(file: a, name: "a")])
        #expect(throws: SquidExportError.tooManySets) { try SquidExporter.export(request, toVolume: stick) }
        var existing = request; existing.set = "S3"
        #expect((try? SquidExporter.export(existing, toVolume: stick)) != nil, "an existing set can still be used")
    }

    @Test func poolExportKeepsNamesUniqueAndConverts() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav", seconds: 0.3)
        let written = try SquidExporter.exportToPool([SquidSource(file: a, name: "Hit"), SquidSource(file: a, name: "Hit")],
                                                     subfolder: "Breaks/707", toVolume: stick)
        #expect(written.map(\.lastPathComponent) == ["Hit.wav", "Hit 2.wav"])
        #expect(written[0].deletingLastPathComponent().path == stick.appendingPathComponent("ALM022/Pool/Breaks/707").path)
        #expect(try info(written[0]).rate == 44_100)
        let again = try SquidExporter.exportToPool([SquidSource(file: a, name: "Hit")], subfolder: "Breaks/707", toVolume: stick)
        #expect(again[0].lastPathComponent == "Hit 3.wav")
        let traversal = try SquidExporter.exportToPool([SquidSource(file: a, name: "x")], subfolder: "../../escape", toVolume: stick)
        #expect(traversal[0].path.hasPrefix(stick.appendingPathComponent("ALM022/Pool").path), "stays inside the Pool")
    }

    @Test func stereoIsMixedDownWithoutClipping() throws {
        let dir = TestSupport.tempDir()
        let url = dir.appendingPathComponent("st.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for i in 0..<4410 { buffer.floatChannelData![0][i] = 0.6; buffer.floatChannelData![1][i] = 0.6 }
        do {   // the file is finished once it goes out of scope
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            try file.write(from: buffer)
        }
        let out = dir.appendingPathComponent("mono.wav")
        try TrimExporter.write(source: url, trim: nil, format: SquidLayout.exportFormat, to: out, maxSeconds: 11, declick: false)
        let b = try TrimRender.read(url: out)
        #expect(b.format.channelCount == 1)
        #expect(abs(b.floatChannelData![0][2000] - 0.6) < 0.02, "same level as before, not doubled")
    }
}
