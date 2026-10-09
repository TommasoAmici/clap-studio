import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidManagerTests {
    private let fm = FileManager.default
    /// Tests must not fill the user's Trash: "trashing" deletes.
    private let trash: SquidManager.Trash = { try FileManager.default.removeItem(at: $0) }

    private func source(_ dir: URL, _ name: String) throws -> SquidSource {
        let url = dir.appendingPathComponent(name + ".wav")
        try writeTestWav(url, seconds: 0.2, sampleRate: 44_100) { _ in 0.5 }
        return SquidSource(file: url, name: name)
    }

    private func stick(withBanks sources: [[SquidSource?]] = [], set: String? = nil) throws -> URL {
        let volume = TestSupport.tempDir()
        try fm.createDirectory(at: SquidStick.rootURL(volume: volume), withIntermediateDirectories: true)
        for (index, slots) in sources.enumerated() {
            try SquidExporter.export(SquidBankRequest(set: set, number: index + 1, name: "B\(index + 1)", slots: slots), toVolume: volume)
        }
        return volume
    }

    @Test func addingFillsTheFreeChannelsOnly() throws {
        let dir = TestSupport.tempDir()
        let a = try source(dir, "a"), b = try source(dir, "b"), c = try source(dir, "c"), d = try source(dir, "d")
        let volume = try stick(withBanks: [[a, nil, c]])
        var bank = SquidStick.read(volume: volume).set(named: nil)?.banks.first
        #expect(bank?.freeSlotNumbers == [2, 4, 5, 6, 7, 8])

        let slots = try SquidExporter.add([b, d], set: nil, number: 1, toVolume: volume)
        #expect(slots == [2, 4])
        bank = SquidStick.read(volume: volume).set(named: nil)?.banks.first
        #expect(bank?.filled == [1, 2, 3, 4] && bank?.name == "B1", "the name is untouched")
        #expect(fm.fileExists(atPath: SquidStick.rootURL(volume: volume).appendingPathComponent("Bank 1/1/a.wav").path), "what was there stays")

        // More samples than free channels: the rest are left out.
        let many = try (0..<8).map { try source(dir, "m\($0)") }
        #expect(try SquidExporter.add(many, set: nil, number: 1, toVolume: volume) == [5, 6, 7, 8])
        #expect(throws: SquidExportError.self) { try SquidExporter.add([a], set: nil, number: 1, toVolume: volume) }
        #expect(throws: SquidExportError.self) { try SquidExporter.add([a], set: nil, number: 9, toVolume: volume) }
    }

    @Test func aLooseOldStyleFileCountsAsFilled() throws {
        let dir = TestSupport.tempDir()
        let volume = try stick(withBanks: [[try source(dir, "a")]])
        let bank = SquidStick.rootURL(volume: volume).appendingPathComponent("Bank 1")
        try Data().write(to: bank.appendingPathComponent("Chan-004.wav"))
        #expect(SquidStick.read(volume: volume).set(named: nil)?.banks.first?.filled == [1, 4])
    }

    @Test func namesAreWrittenAndReadBackExactly() throws {
        let dir = TestSupport.tempDir()
        let volume = try stick(withBanks: [[try source(dir, "a")]])
        try SquidManager.renameBank(set: nil, number: 1, to: "Café Drums & More", volume: volume)
        #expect(SquidStick.read(volume: volume).set(named: nil)?.banks.first?.name == "Café Drums & More", "not cut, not cleaned")
        try SquidManager.createSet(name: "Loops 2025 long", volume: volume)
        #expect(SquidStick.read(volume: volume).sets.compactMap(\.name) == ["Loops 2025 long"])
        #expect(throws: SquidExportError.self) { try SquidManager.createSet(name: "a/b", volume: volume) }
        #expect(throws: SquidExportError.self) { try SquidManager.createSet(name: "loops 2025 LONG", volume: volume) }
    }

    @Test func setsCanBeCreatedRenamedAndTrashed() throws {
        let dir = TestSupport.tempDir()
        let volume = try stick()
        try SquidManager.createSet(name: "Loops", volume: volume)
        try SquidExporter.export(SquidBankRequest(set: "Loops", number: 2, name: "Two", slots: [try source(dir, "a")]), toVolume: volume)
        try SquidManager.renameSet("Loops", to: "Breaks", volume: volume)
        var contents = SquidStick.read(volume: volume)
        #expect(contents.sets.compactMap(\.name) == ["Breaks"] && contents.set(named: "Breaks")?.banks.map(\.number) == [2], "banks go with it")
        try SquidManager.renameSet("Breaks", to: "breaks", volume: volume)
        #expect(SquidStick.read(volume: volume).sets.compactMap(\.name) == ["breaks"], "a change of case only")
        try SquidManager.createSet(name: "Other", volume: volume)
        #expect(throws: SquidExportError.self) { try SquidManager.renameSet("breaks", to: "OTHER", volume: volume) }
        try SquidManager.trashSet("breaks", volume: volume, trash: trash)
        contents = SquidStick.read(volume: volume)
        #expect(contents.sets.compactMap(\.name) == ["Other"])
        #expect(throws: SquidExportError.self) { try SquidManager.trashSet("nope", volume: volume, trash: trash) }
    }

    @Test func aStickKeepsAtMostSixteenSets() throws {
        let volume = try stick()
        for n in 1...SquidLayout.maxSets { try SquidManager.createSet(name: "S\(n)", volume: volume) }
        #expect(throws: SquidExportError.tooManySets) { try SquidManager.createSet(name: "One more", volume: volume) }
    }

    @Test func banksCanBeCreatedDuplicatedMovedAndTrashed() throws {
        let dir = TestSupport.tempDir()
        let volume = try stick(withBanks: [[try source(dir, "a"), try source(dir, "b")]])
        try SquidManager.createSet(name: "Loops", volume: volume)

        #expect(try SquidManager.createBank(set: nil, volume: volume) == 2, "the lowest free number")
        #expect(try SquidManager.createBank(set: "Loops", name: "Fresh", volume: volume) == 1)
        #expect(try SquidManager.duplicateBank(set: nil, number: 1, volume: volume) == 3)
        var contents = SquidStick.read(volume: volume)
        #expect(contents.set(named: nil)?.banks.map(\.number) == [1, 2, 3])
        #expect(contents.set(named: nil)?.banks.last?.filled == [1, 2] && contents.set(named: nil)?.banks.last?.name == "B1")

        #expect(try SquidManager.moveBank(set: nil, number: 3, toSet: "Loops", volume: volume) == 2)
        contents = SquidStick.read(volume: volume)
        #expect(contents.set(named: nil)?.banks.map(\.number) == [1, 2])
        #expect(contents.set(named: "Loops")?.banks.map(\.number) == [1, 2])

        try SquidManager.trashSample(set: nil, number: 1, slot: 2, volume: volume, trash: trash)
        #expect(SquidStick.read(volume: volume).set(named: nil)?.banks.first?.filled == [1])
        try SquidManager.trashBank(set: nil, number: 2, volume: volume, trash: trash)
        #expect(SquidStick.read(volume: volume).set(named: nil)?.banks.map(\.number) == [1])
        #expect(throws: SquidExportError.self) { try SquidManager.renameBank(set: nil, number: 2, to: "x", volume: volume) }
    }

    @Test func existingFoldersAreFoundWhateverTheirCase() throws {
        let volume = try stick()
        let alm = SquidStick.rootURL(volume: volume)
        try fm.createDirectory(at: alm.appendingPathComponent("set Drums/bank 05"), withIntermediateDirectories: true)
        #expect(SquidStick.read(volume: volume).set(named: "DRUMS")?.banks.map(\.number) == [5])
        #expect(SquidStick.bankURL(set: "Drums", number: 5, volume: volume) != nil)
        #expect(try SquidManager.createBank(set: "drums", volume: volume) == 1)
        #expect(SquidStick.read(volume: volume).sets.compactMap(\.name) == ["Drums"], "no second set folder was made")
    }
}
