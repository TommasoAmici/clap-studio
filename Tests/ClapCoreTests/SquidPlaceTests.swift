import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidPlaceTests {
    private func makeSource(_ dir: URL, _ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try writeTestWav(url, seconds: 0.2) { _ in 0.4 }
        return url
    }
    private func exists(_ stick: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: stick.appendingPathComponent("ALM022/" + path).path)
    }

    @Test func eachSampleLandsOnItsOwnChannelOfItsOwnBank() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let snare = try makeSource(dir, "snare.wav")
        let placed = (1...3).map { SquidPlacedSource(source: SquidSource(file: snare, name: "Snare \($0)"), slot: SquidSlot(bank: $0, channel: 2)) }
        try SquidExporter.place(placed, set: "Drums", bankNames: [1: "Snares", 2: "Snares", 3: "Snares"], toVolume: stick)
        for bank in 1...3 {
            #expect(exists(stick, "Set Drums/Bank \(bank)/2/Snare \(bank).wav"), "Snare \(bank) is on channel 2 of bank \(bank).")
            #expect(!exists(stick, "Set Drums/Bank \(bank)/1"), "Other channels stay empty.")
        }
        let contents = SquidStick.read(volume: stick)
        #expect(contents.set(named: "Drums")?.banks.map(\.name) == ["Snares", "Snares", "Snares"])
    }

    @Test func anExistingBankKeepsItsNameAndSamples() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav")
        try SquidExporter.export(SquidBankRequest(set: nil, number: 1, name: "Mine", slots: [SquidSource(file: a, name: "old")]), toVolume: stick)
        try SquidExporter.place([SquidPlacedSource(source: SquidSource(file: a, name: "new"), slot: SquidSlot(bank: 1, channel: 5))],
                                set: nil, bankNames: [1: "Ignored"], toVolume: stick)
        #expect(exists(stick, "Bank 1/1/old.wav") && exists(stick, "Bank 1/5/new.wav"))
        #expect(SquidStick.read(volume: stick).set(named: nil)?.banks.first?.name == "Mine", "A bank that is already there keeps its name.")
    }

    @Test func aTakenChannelStopsEverythingBeforeAnythingIsWritten() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav")
        try SquidExporter.export(SquidBankRequest(set: nil, number: 2, name: "B", slots: [nil, SquidSource(file: a, name: "old")]), toVolume: stick)
        let placed = [SquidPlacedSource(source: SquidSource(file: a, name: "one"), slot: SquidSlot(bank: 1, channel: 2)),
                      SquidPlacedSource(source: SquidSource(file: a, name: "two"), slot: SquidSlot(bank: 2, channel: 2))]
        #expect(throws: SquidExportError.self) { try SquidExporter.place(placed, set: nil, bankNames: [:], toVolume: stick) }
        #expect(!exists(stick, "Bank 1"), "Nothing is written when one sample cannot go where it was meant to.")
        #expect(exists(stick, "Bank 2/2/old.wav"), "The sample already on the stick is untouched.")
    }

    @Test func twoSamplesOnOneChannelAreRefused() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav")
        let placed = ["x", "y"].map { SquidPlacedSource(source: SquidSource(file: a, name: $0), slot: SquidSlot(bank: 1, channel: 1)) }
        #expect(throws: SquidExportError.self) { try SquidExporter.place(placed, set: nil, bankNames: [:], toVolume: stick) }
        #expect(!exists(stick, "Bank 1"))
    }

    @Test func badSlotsAndSetsAreRefused() throws {
        let dir = TestSupport.tempDir(), stick = TestSupport.tempDir()
        let a = try makeSource(dir, "a.wav")
        let source = SquidSource(file: a, name: "a")
        #expect(throws: SquidExportError.self) {
            try SquidExporter.place([SquidPlacedSource(source: source, slot: SquidSlot(bank: 100, channel: 1))], set: nil, bankNames: [:], toVolume: stick)
        }
        #expect(throws: SquidExportError.self) {
            try SquidExporter.place([SquidPlacedSource(source: source, slot: SquidSlot(bank: 1, channel: 9))], set: nil, bankNames: [:], toVolume: stick)
        }
        #expect(throws: SquidExportError.self) {
            try SquidExporter.place([SquidPlacedSource(source: source, slot: SquidSlot(bank: 1, channel: 1))], set: "a/b", bankNames: [:], toVolume: stick)
        }
    }
}
