import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidCollectionSenderTests {
    private func sources(_ ids: [Int64], file: URL, names: String = "S") -> [Int64: SquidSource] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, SquidSource(file: file, name: "\(names) \($0)")) })
    }
    private func tinyWav() throws -> URL {
        let url = TestSupport.tempDir().appendingPathComponent("a.wav")
        try writeTestWav(url, seconds: 0.1) { _ in 0.3 }
        return url
    }
    private func exists(_ stick: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: stick.appendingPathComponent("ALM022/" + path).path)
    }

    @Test func aCollectionWithSubCollectionsIsWrittenAsABankPerSubCollection() throws {
        let stick = TestSupport.tempDir(), file = try tinyWav()
        let plan = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [
            .init(name: "Opening", samples: [1, 2, 3]), .init(name: "Peak", samples: [4, 5])], contents: SquidStickContents())
        try SquidCollectionSender.send(plan, sources: sources([1, 2, 3, 4, 5], file: file), toVolume: stick)
        #expect(exists(stick, "Set Party/Bank 1/1/S 1.wav") && exists(stick, "Set Party/Bank 1/3/S 3.wav"), "Channels follow the sample order.")
        #expect(exists(stick, "Set Party/Bank 2/2/S 5.wav"))
        let set = SquidStick.read(volume: stick).set(named: "Party")
        #expect(set?.banks.map(\.name) == ["Opening", "Peak"])
    }

    @Test func aBlockedPlanWritesNothing() throws {
        let stick = TestSupport.tempDir(), file = try tinyWav()
        let big = (1...9).map(Int64.init)
        let plan = SquidCollectionPlan.make(name: "Party", ownSamples: [], children: [
            .init(name: "Fine", samples: [1]), .init(name: "Peak", samples: big)], contents: SquidStickContents())
        #expect(throws: SquidExportError.self) { try SquidCollectionSender.send(plan, sources: sources(big, file: file), toVolume: stick) }
        #expect(!FileManager.default.fileExists(atPath: stick.appendingPathComponent("ALM022").path), "Not even the Squid folder is made.")
    }

    @Test func aPlainCollectionIsWrittenAsAPoolFolder() throws {
        let stick = TestSupport.tempDir(), file = try tinyWav()
        let plan = SquidCollectionPlan.make(name: "Breaks", ownSamples: [1, 2], children: [], contents: SquidStickContents())
        try SquidCollectionSender.send(plan, sources: sources([1, 2], file: file), toVolume: stick)
        #expect(exists(stick, "Pool/Breaks/S 1.wav") && exists(stick, "Pool/Breaks/S 2.wav"))
    }

    @Test func aBigCollectionIsWrittenAsNumberedPoolFolders() throws {
        let stick = TestSupport.tempDir(), file = try tinyWav()
        let all = (1...258).map(Int64.init)
        let plan = SquidCollectionPlan.make(name: "Loops", ownSamples: all, children: [], contents: SquidStickContents())
        try SquidCollectionSender.send(plan, sources: sources(all, file: file), toVolume: stick)
        #expect(exists(stick, "Pool/Loops/Loops 1/S 1.wav") && exists(stick, "Pool/Loops/Loops 1/S 256.wav"))
        #expect(exists(stick, "Pool/Loops/Loops 2/S 258.wav") && !exists(stick, "Pool/Loops/Loops 1/S 257.wav"))
        let folders = SquidStick.read(volume: stick).poolFolder(at: ["Loops"])?.children
        #expect(folders?.map(\.sampleCount) == [256, 2])
    }

    @Test func aFailurePartWayTakesTheNewPoolFolderBackOut() throws {
        let stick = TestSupport.tempDir(), file = try tinyWav()
        let all = (1...257).map(Int64.init)
        var made = sources(all, file: file)
        made[257] = SquidSource(file: file.deletingLastPathComponent().appendingPathComponent("gone.wav"), name: "Gone")
        let plan = SquidCollectionPlan.make(name: "Loops", ownSamples: all, children: [], contents: SquidStickContents())
        #expect(throws: SquidExportError.self) { try SquidCollectionSender.send(plan, sources: made, toVolume: stick) }
        #expect(!exists(stick, "Pool/Loops"), "A half-written folder is not left on the stick.")
    }

    @Test func aSampleWithNoSourceStopsTheSend() throws {
        let stick = TestSupport.tempDir(), file = try tinyWav()
        let plan = SquidCollectionPlan.make(name: "Breaks", ownSamples: [1, 2], children: [], contents: SquidStickContents())
        #expect(throws: SquidExportError.self) { try SquidCollectionSender.send(plan, sources: sources([1], file: file), toVolume: stick) }
        #expect(!exists(stick, "Pool/Breaks"))
    }
}
