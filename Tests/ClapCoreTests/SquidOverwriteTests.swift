import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidOverwriteTests {
    private func makeSource(_ dir: URL, _ name: String, level: Float = 0.4) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try writeTestWav(url, seconds: 0.2) { _ in level }
        return url
    }
    private func path(_ stick: URL, _ relative: String) -> String { stick.appendingPathComponent("ALM022/" + relative).path }
    private func exists(_ stick: URL, _ relative: String) -> Bool { FileManager.default.fileExists(atPath: path(stick, relative)) }
    private func entries(_ stick: URL, _ relative: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path(stick, relative))) ?? []).sorted()
    }
    /// A stick whose bank 1 holds `old` on channels 1 and 2.
    private func stickWithOldSamples(_ dir: URL) throws -> URL {
        let stick = TestSupport.tempDir()
        let old = try makeSource(dir, "old.wav", level: 0.1)
        try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "Old", slots: [
            SquidSource(file: old, name: "old one"), SquidSource(file: old, name: "old two")]), toVolume: stick)
        return stick
    }

    @Test func overwritingReplacesTheSampleOnThatChannelOnly() throws {
        let dir = TestSupport.tempDir()
        let stick = try stickWithOldSamples(dir)
        let fresh = try makeSource(dir, "fresh.wav", level: 0.5)
        try SquidExporter.place([SquidPlacedSource(source: SquidSource(file: fresh, name: "fresh"), slot: SquidSlot(bank: 1, channel: 1))],
                                set: nil, bankNames: [:], toVolume: stick, overwrite: true)
        #expect(entries(stick, "Bank 1/1") == ["fresh.wav"], "The old sample is gone from the channel and the new one is the only file in it.")
        #expect(entries(stick, "Bank 1/2") == ["old two.wav"], "Other channels are not touched.")
        #expect(SquidStick.read(volume: stick).set(named: nil)?.banks.first?.name == "Old", "The bank keeps its name.")
        #expect(entries(stick, "Bank 1").allSatisfy { !$0.hasPrefix(".") }, "No temporary folder is left on the stick.")
    }

    @Test func withoutPermissionATakenChannelStillStopsTheSend() throws {
        let dir = TestSupport.tempDir()
        let stick = try stickWithOldSamples(dir)
        let fresh = try makeSource(dir, "fresh.wav")
        #expect(throws: SquidExportError.self) {
            try SquidExporter.place([SquidPlacedSource(source: SquidSource(file: fresh, name: "fresh"), slot: SquidSlot(bank: 1, channel: 1))],
                                    set: nil, bankNames: [:], toVolume: stick)
        }
        #expect(entries(stick, "Bank 1/1") == ["old one.wav"], "Collections and other callers keep the old, safe behaviour.")
    }

    @Test func overwritingSeveralBanksAndFillingNewOnesInOneSend() throws {
        let dir = TestSupport.tempDir()
        let stick = try stickWithOldSamples(dir)
        let fresh = try makeSource(dir, "fresh.wav", level: 0.5)
        let placed = (1...3).map { SquidPlacedSource(source: SquidSource(file: fresh, name: "snare \($0)"), slot: SquidSlot(bank: $0, channel: 2)) }
        try SquidExporter.place(placed, set: nil, bankNames: [1: "Ignored", 2: "Snares", 3: "Snares"], toVolume: stick, overwrite: true)
        #expect(entries(stick, "Bank 1/2") == ["snare 1.wav"] && entries(stick, "Bank 1/1") == ["old one.wav"])
        #expect(entries(stick, "Bank 2/2") == ["snare 2.wav"] && entries(stick, "Bank 3/2") == ["snare 3.wav"], "Free banks are made as before.")
    }

    @Test func anOldFirmwareChannelFileIsReplacedToo() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let old = try makeSource(dir, "old.wav", level: 0.1)
        let bank = stick.appendingPathComponent("ALM022/Bank 1")
        try FileManager.default.createDirectory(at: bank, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: old, to: bank.appendingPathComponent("Chan-003.wav"))
        let fresh = try makeSource(dir, "fresh.wav", level: 0.5)
        try SquidExporter.place([SquidPlacedSource(source: SquidSource(file: fresh, name: "fresh"), slot: SquidSlot(bank: 1, channel: 3))],
                                set: nil, bankNames: [:], toVolume: stick, overwrite: true)
        #expect(entries(stick, "Bank 1") == ["3"], "The loose Chan-003.wav is replaced by the channel folder, so channel 3 holds one sample.")
        #expect(entries(stick, "Bank 1/3") == ["fresh.wav"])
    }

    @Test func aFailedSwapPutsEveryOldSampleBack() throws {
        let dir = TestSupport.tempDir()
        let stick = try stickWithOldSamples(dir)
        let bank = stick.appendingPathComponent("ALM022/Bank 1")
        let fresh = try makeSource(dir, "fresh.wav", level: 0.5)
        var swap = SquidOverwrite(fileManager: .default)
        for channel in 1...2 {
            let folder = bank.appendingPathComponent(String(channel))
            try swap.prepare(file: fresh, channelFolder: folder, oldItems: [folder])
        }
        // Something removes the second clone before the swap, so channel 2 cannot be completed after channel 1 was.
        try FileManager.default.removeItem(at: bank.appendingPathComponent(".clap-new-\(swap.token)-2"))
        #expect(throws: (any Error).self) { try swap.commit() }
        swap.rollback()
        #expect(entries(stick, "Bank 1/1") == ["old one.wav"] && entries(stick, "Bank 1/2") == ["old two.wav"],
                "A bank is never left half written: both channels hold what they held before.")
        #expect(entries(stick, "Bank 1").allSatisfy { !$0.hasPrefix(".") }, "Temporary folders are removed.")
    }

    @Test func aCloneThatDoesNotMatchIsRefusedBeforeAnythingChanges() throws {
        let dir = TestSupport.tempDir()
        let stick = try stickWithOldSamples(dir)
        let folder = stick.appendingPathComponent("ALM022/Bank 1/1")
        var swap = SquidOverwrite(fileManager: .default)
        let missing = dir.appendingPathComponent("nope.wav")
        #expect(throws: (any Error).self) { try swap.prepare(file: missing, channelFolder: folder, oldItems: [folder]) }
        swap.rollback()
        #expect(entries(stick, "Bank 1/1") == ["old one.wav"], "Preparing only writes next to the old sample.")
    }
}
