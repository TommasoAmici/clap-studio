import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidJoinedSendTests {
    private func kicks(_ count: Int, in dir: URL, seconds: Double = 1) throws -> [JoinSource] {
        try (1...count).map { index in
            let url = dir.appendingPathComponent("kick \(index).wav")
            try writeTestWav(url, seconds: seconds) { _ in 0.3 }
            return JoinSource(url: url)
        }
    }
    private func file(_ stick: URL, _ path: String) -> URL { stick.appendingPathComponent("ALM022/" + path) }

    @Test func twentyKicksSplitIntoJoinedFilesOnChannelOneOfFollowingBanks() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir(), work = TestSupport.tempDir()
        let sources = try kicks(20, in: dir)
        let originals = try sources.map { try Data(contentsOf: $0.url) }
        let slots = try SquidJoinedSender.send(sources, name: "kicks", channel: 1, set: "Drums", firstBank: 1, bankName: "Kicks",
                                               category: nil, toVolume: stick, workFolder: work)
        #expect(slots == [SquidSlot(bank: 1, channel: 1), SquidSlot(bank: 2, channel: 1), SquidSlot(bank: 3, channel: 1)],
                "One second kicks with a quarter second gap fit nine to an 11 second file: 9, 9 and 2.")
        let counts = try (1...3).map { bank -> Int in
            let url = file(stick, "Set Drums/Bank \(bank)/1/kicks 0\(bank).wav")
            #expect(FileManager.default.fileExists(atPath: url.path), "Bank \(bank) holds kicks 0\(bank) on channel 1.")
            let audio = try AVAudioFile(forReading: url)
            #expect(audio.processingFormat.channelCount == 1 && audio.fileFormat.sampleRate == 44_100, "The module's format.")
            return CueFileReader.read(url: url).count
        }
        #expect(counts == [9, 9, 2], "Every kick keeps its own cue marker in the joined file.")
        #expect(SquidStick.read(volume: stick).set(named: "Drums")?.banks.map(\.name) == ["Kicks", "Kicks", "Kicks"])
        #expect(try sources.map { try Data(contentsOf: $0.url) } == originals, "Library files are only read.")
        #expect((try FileManager.default.contentsOfDirectory(atPath: work.path)).isEmpty, "The temporary joined files are cleaned up.")
    }

    @Test func theCategoryIsKeptWithoutLosingTheCueMarkers() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        _ = try SquidJoinedSender.send(try kicks(3, in: dir), name: "Joined", channel: 4, set: nil, firstBank: 2, bankName: "",
                                       category: "Kick", toVolume: stick)
        let url = file(stick, "Bank 2/4/Joined 01.wav")
        #expect(WavInfo.category(of: url) == "Kick")
        #expect(CueFileReader.read(url: url).count == 3, "Tagging the file leaves the cue markers alone.")
    }

    @Test func aBankWhoseChannelIsTakenIsOverwritten() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let taken = dir.appendingPathComponent("old.wav")
        try writeTestWav(taken, seconds: 0.2) { _ in 0.3 }
        try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "Old", slots: [SquidSource(file: taken, name: "old")]), toVolume: stick)
        let slots = try SquidJoinedSender.send(try kicks(2, in: dir), name: "Joined", channel: 1, set: nil, firstBank: 1, bankName: "New",
                                               category: nil, toVolume: stick)
        #expect(slots == [SquidSlot(bank: 1, channel: 1)], "The joined file goes where it was asked to, over the sample that was there.")
        #expect(!FileManager.default.fileExists(atPath: file(stick, "Bank 1/1/old.wav").path), "The old sample is replaced.")
        #expect(FileManager.default.fileExists(atPath: file(stick, "Bank 1/1/Joined 01.wav").path))
        #expect(SquidStick.read(volume: stick).set(named: nil)?.banks.first?.name == "Old", "An existing bank keeps its name.")
    }

    @Test func notEnoughBanksStopsBeforeAnythingIsWritten() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let sources = try kicks(20, in: dir)
        #expect(throws: SquidExportError.self) {
            try SquidJoinedSender.send(sources, name: "Joined", channel: 1, set: nil, firstBank: 98, bankName: "", category: nil, toVolume: stick)
        }
        #expect(!FileManager.default.fileExists(atPath: file(stick, "Bank 98").path), "Part of a joined set is not sent.")
    }

    @Test func theFileCountCanBeEstimatedFromLengthsAlone() throws {
        let seconds = Array(repeating: 1.0, count: 20)
        #expect(JoinPlanner.estimatedFileCount(seconds: seconds, settings: .almSalmple) == 3)
        #expect(JoinPlanner.estimatedFileCount(seconds: [], settings: .almSalmple) == 0)
        #expect(JoinPlanner.estimatedFileCount(seconds: [25], settings: .almSalmple) == 3, "A long sound continues across files.")
    }
}
