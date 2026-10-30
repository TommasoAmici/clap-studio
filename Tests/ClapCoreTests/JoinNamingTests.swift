import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct JoinNamingTests {
    @Test func numbersHaveOneLeadingZeroAndGrowPastNinetyNine() {
        #expect(JoinNaming.fileName(base: "kicks", number: 1) == "kicks 01.wav", "One digit gets one leading zero.")
        #expect(JoinNaming.fileName(base: "kicks", number: 10) == "kicks 10.wav")
        #expect(JoinNaming.fileName(base: "kicks", number: 99) == "kicks 99.wav")
        #expect(JoinNaming.fileName(base: "kicks", number: 100) == "kicks 100.wav", "Beyond two digits the natural width is used.")
    }

    @Test func anEmptyNameFallsBackToJoined() {
        #expect(JoinNaming.baseName("") == "Joined")
        #expect(JoinNaming.baseName("   ") == "Joined", "A name of spaces is as good as none.")
    }

    @Test func aNameIsTrimmedAndCannotEscapeTheFolder() {
        #expect(JoinNaming.baseName("  kicks ") == "kicks")
        #expect(JoinNaming.baseName("a/b:c") == "a-b-c", "Path separators would write outside the chosen folder.")
        #expect(JoinNaming.baseName("..") == "Joined", "A name made only of dots hides the file or climbs a folder.")
        #expect(JoinNaming.baseName(String(repeating: "x", count: 300)).count <= JoinNaming.maxNameLength,
                "File names longer than the file system allows would fail the export.")
    }

    @Test func exportedFilesUseTheChosenNameAndTwoDigitNumbers() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Kick.wav")
        try writeTestWav(source, seconds: 0.1) { _ in 0.25 }
        let outputs = try JoinExporter.export([JoinSource(url: source), JoinSource(url: source)],
                                              settings: JoinSettings(maxCuePoints: 1), name: "kicks",
                                              to: dir.appendingPathComponent("out"))
        #expect(outputs.map(\.lastPathComponent) == ["kicks 01.wav", "kicks 02.wav"])
    }

    @Test func theDefaultNameIsJoined() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Kick.wav")
        try writeTestWav(source, seconds: 0.1) { _ in 0.25 }
        let outputs = try JoinExporter.export([JoinSource(url: source)], settings: JoinSettings(),
                                              to: dir.appendingPathComponent("out"))
        #expect(outputs.map(\.lastPathComponent) == ["Joined 01.wav"])
    }

    @Test func aTakenNameGetsAnExtraNumberInsteadOfReplacingTheFile() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let taken = out.appendingPathComponent("kicks 01.wav")
        try Data([1, 2, 3]).write(to: taken)
        let source = dir.appendingPathComponent("Kick.wav")
        try writeTestWav(source, seconds: 0.1) { _ in 0.25 }
        let outputs = try JoinExporter.export([JoinSource(url: source)], settings: JoinSettings(), name: "kicks", to: out)
        #expect(outputs.map(\.lastPathComponent) == ["kicks 01 2.wav"])
        #expect(try Data(contentsOf: taken) == Data([1, 2, 3]), "An existing file is never replaced.")
    }
}
