import Foundation
import Testing
@testable import ClapCore

@Suite struct SquidLayoutTests {
    @Test func locationsFollowTheManual() {
        #expect(SquidLayout.location(ofRelativePath: "Bank 1/3/Closed.wav") == .bank(set: nil, number: 1, slot: 3))
        #expect(SquidLayout.location(ofRelativePath: "Bank 99/8/x.wav") == .bank(set: nil, number: 99, slot: 8))
        #expect(SquidLayout.location(ofRelativePath: "Set Loops/Bank 12/5/Break.wav") == .bank(set: "Loops", number: 12, slot: 5))
        #expect(SquidLayout.location(ofRelativePath: "Bank 4/Chan-006.wav") == .bank(set: nil, number: 4, slot: 6), "older firmware layout")
        #expect(SquidLayout.location(ofRelativePath: "Pool/Kick.wav") == .pool(folders: []))
        #expect(SquidLayout.location(ofRelativePath: "Pool/Breaks/707/a.wav") == .pool(folders: ["Breaks", "707"]))
        #expect(SquidLayout.location(ofRelativePath: "Bank 100/1/a.wav") == .other, "banks stop at 99")
        #expect(SquidLayout.location(ofRelativePath: "Bank 1/9/a.wav") == .bank(set: nil, number: 1, slot: nil), "only channels 1-8")
        #expect(SquidLayout.location(ofRelativePath: "notes.wav") == .other)
    }

    @Test func bankPaths() {
        #expect(SquidLayout.bankPath(set: nil, number: 7) == "Bank 7")
        #expect(SquidLayout.bankPath(set: "Loops", number: 7) == "Set Loops/Bank 7")
        #expect(SquidLayout.bankPath(set: nil, number: 0) == nil)
        #expect(SquidLayout.bankPath(set: nil, number: 100) == nil)
        #expect(SquidLayout.bankPath(set: "///", number: 1) == nil, "an unusable set name")
    }

    @Test func folderNamesIgnoreCase() {
        #expect(SquidLayout.location(ofRelativePath: "bank 3/2/a.wav") == .bank(set: nil, number: 3, slot: 2))
        #expect(SquidLayout.location(ofRelativePath: "SET Loops/BANK 12/5/a.wav") == .bank(set: "Loops", number: 12, slot: 5))
        #expect(SquidLayout.setName(fromFolder: "set Loops") == "Loops", "the name keeps its own case")
        #expect(SquidLayout.sameSet("Loops", "loops") && SquidLayout.sameSet(nil, nil) && !SquidLayout.sameSet(nil, "Loops"))
    }

    @Test func setAndBankNamesAreKeptAsTypedAndOnlyReported() {
        // Nothing is cleaned: the folder and info.txt carry exactly what was typed.
        #expect(SquidLayout.setFolder(name: "Café & more!") == "Set Café & more!")
        #expect(SquidLayout.bankPath(set: "Loops 2025 long", number: 7) == "Set Loops 2025 long/Bank 7")
        #expect(SquidLayout.infoContents(name: "Café Drums & More") == "Café Drums & More\n")

        #expect(SquidLayout.check(setName: "Loops").isClean)
        let long = SquidLayout.check(setName: "Loops 2025 long")
        #expect(!long.isBlocked && long.warnings.count == 1 && long.message.contains("at most 8"))
        let bad = SquidLayout.check(setName: "a/b: c")
        #expect(bad.isBlocked && SquidLayout.setFolder(name: "a/b: c") == nil && SquidLayout.bankPath(set: "a/b", number: 1) == nil)
        #expect(SquidLayout.check(setName: "  ").isBlocked, "an empty name")
        #expect(SquidLayout.check(setName: "loops", existing: ["Loops"]).isBlocked, "same folder on a case-insensitive stick")
        #expect(!SquidLayout.check(setName: "loops", existing: ["Loops"], renaming: "Loops").isBlocked, "changing only the case is a rename")

        #expect(SquidLayout.check(bankName: "MiscKit").isClean)
        #expect(SquidLayout.check(bankName: "").isClean)
        let bank = SquidLayout.check(bankName: "Café Drums")
        #expect(!bank.isBlocked && !bank.isClean && bank.message.contains("“Caf Drum”"))
        #expect(SquidLayout.moduleShows(bankName: "Café Drums") == "Caf Drum")
        #expect(SquidLayout.moduleShows(bankName: "Kick") == "Kick")
    }

    @Test func fileNamesAreMadeSafe() {
        #expect(SquidLayout.cleanFileStem("808 Kick: Long (v2)!.wav") == "808 Kick Long v2wav")
        #expect(SquidLayout.cleanFileStem("日本語") == "Sample", "nothing usable falls back")
        #expect(SquidLayout.cleanFileStem(String(repeating: "a", count: 80)).count == SquidLayout.maxFileStemLength)
        #expect(SquidLayout.infoContents(name: "MiscKit") == "MiscKit\n")
    }
}

@Suite struct UsbDriveTests {
    @Test func onlyPluggedInVolumesCount() {
        func ext(_ path: String, internal i: Bool? = false, removable r: Bool? = true, ejectable e: Bool? = true, local l: Bool? = true) -> Bool {
            UsbDrive.isExternal(path: path, isInternal: i, isRemovable: r, isEjectable: e, isLocal: l)
        }
        #expect(ext("/Volumes/SQUID"))
        #expect(!ext("/"), "the system volume")
        #expect(!ext("/System/Volumes/Data"))
        #expect(!ext("/Volumes/Macintosh HD", internal: true, removable: false, ejectable: false))
        #expect(!ext("/Volumes/Share", local: false), "network shares")
        #expect(ext("/Volumes/SD", internal: true, removable: true), "built-in card readers still hold removable media")
        #expect(ext("/Volumes/SSD", internal: false, removable: false, ejectable: false), "external disk")
    }

    @Test func fat32Detection() {
        func drive(_ f: String) -> UsbDrive { UsbDrive(url: URL(fileURLWithPath: "/Volumes/X"), name: "X", formatDescription: f, capacity: nil, available: nil) }
        #expect(drive("MS-DOS (FAT32)").isFAT32)
        #expect(!drive("ExFAT").isFAT32)
        #expect(!drive("Mac OS Extended (Journaled)").isFAT32)
        #expect(!drive("MS-DOS (FAT16)").isFAT32)
    }
}
