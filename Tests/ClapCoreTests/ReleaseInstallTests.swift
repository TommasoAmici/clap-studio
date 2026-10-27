import Foundation
import Testing
@testable import ClapCore

@Suite struct ReleaseInstallTests {
    @Test func quarantineIsRemovedFromTheBundleAndItsContents() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try signedApp(in: root, version: ReleaseVersion(tag: "v1.2.3-build.4")!)
        try tool("/usr/bin/xattr", ["-wr", "com.apple.quarantine", "0081;00000000;ClapStudio;", app.path])
        try ReleaseInstaller.clearDownloadQuarantine(app)
        for path in [app, app.appendingPathComponent("Contents/MacOS/ClapStudio")] {
            let attributes = Process()
            attributes.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            attributes.arguments = ["-p", "com.apple.quarantine", path.path]
            attributes.standardOutput = FileHandle.nullDevice
            attributes.standardError = FileHandle.nullDevice
            try attributes.run()
            attributes.waitUntilExit()
            #expect(attributes.terminationStatus != 0, "download quarantine must be removed from the app and executable")
        }
        try ReleaseInstaller.validateBundle(app, version: ReleaseVersion(tag: "v1.2.3-build.4")!)
        try ReleaseInstaller.clearDownloadQuarantine(app)
    }

    @Test func verifiedAppIsInstalledAndReplacesOnlyClapStudio() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let version = ReleaseVersion(tag: "v1.2.3-build.4")!
        let app = try signedApp(in: root.appendingPathComponent("source"), version: version)
        let archive = root.appendingPathComponent("release.zip")
        try tool("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path])
        try ReleaseArchive.validate(archive)
        let applications = root.appendingPathComponent("Applications")
        let destination = try ReleaseInstaller.install(archive: archive, version: version, applications: applications)
        #expect(destination.path == applications.appendingPathComponent("ClapStudio.app").path)
        try ReleaseInstaller.validateBundle(destination, version: version)
        let marker = destination.appendingPathComponent("old-marker")
        try Data("old".utf8).write(to: marker)
        try tool("/usr/bin/xattr", ["-wr", "com.apple.quarantine", "0081;00000000;ClapStudio;", destination.path])
        _ = try ReleaseInstaller.install(archive: archive, version: version, applications: applications)
        #expect(!FileManager.default.fileExists(atPath: marker.path), "replacement must contain the new app's files")
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == ["ClapStudio.app"],
                "successful installation removes staging and backup folders")
        let attributes = Process()
        attributes.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        attributes.arguments = ["-lr", destination.path]
        let output = Pipe()
        attributes.standardOutput = output
        try attributes.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        attributes.waitUntilExit()
        #expect(attributes.terminationStatus == 0)
        #expect(!String(decoding: data, as: UTF8.self).contains("com.apple.quarantine"),
                "verified updates must reopen without download quarantine")
    }

    @Test func wrongVersionKeepsTheInstalledApp() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let version = ReleaseVersion(tag: "v1.2.3-build.4")!
        let applications = root.appendingPathComponent("Applications")
        let old = try signedApp(in: applications, version: version)
        let oldPlist = try Data(contentsOf: old.appendingPathComponent("Contents/Info.plist"))
        let source = try signedApp(in: root.appendingPathComponent("source"), version: version)
        let archive = root.appendingPathComponent("release.zip")
        try tool("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path])
        #expect(throws: ReleaseInstallError.self) {
            try ReleaseInstaller.install(archive: archive, version: ReleaseVersion(tag: "v1.2.3-build.5")!, applications: applications)
        }
        #expect(try Data(contentsOf: old.appendingPathComponent("Contents/Info.plist")) == oldPlist)
        try ReleaseInstaller.validateBundle(old, version: version)
    }

    @Test(arguments: ["../outside", "/tmp/outside", "ClapStudio.app/../outside", "ClapStudio.app/Contents\\outside"])
    func archivePathsCannotLeaveTheStagingFolder(path: String) throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("bad.zip")
        try zip(path: path).write(to: archive)
        #expect(throws: ReleaseInstallError.self) { try ReleaseArchive.validate(archive) }
    }

    @Test func symlinksDuplicateEntriesAndDifferentLocalNamesAreRefused() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("bad.zip")
        for data in [zip(path: "ClapStudio.app/link", mode: 0xa000),
                     zip(path: "ClapStudio.app/file", localPath: "../outside"),
                     zip(path: "ClapStudio.app/file", duplicate: true)] {
            try data.write(to: archive)
            #expect(throws: ReleaseInstallError.self) { try ReleaseArchive.validate(archive) }
        }
        try zip(path: "ClapStudio.app/file").write(to: archive)
        try ReleaseArchive.validate(archive)
    }

    @Test func alternatePathAndUnixLinkMetadataAreRefusedBeforeExtraction() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("bad.zip")
        for tag: UInt32 in [0x7075, 0x000d] {
            var extra = [UInt8](repeating: 0, count: 4)
            put(tag, in: &extra, at: 0, count: 2)
            put(10, in: &extra, at: 2, count: 2)
            extra += Array("../outside".utf8)
            for data in [zip(path: "ClapStudio.app/file", extra: extra),
                         zip(path: "ClapStudio.app/file", localExtra: extra)] {
                try data.write(to: archive)
                #expect(throws: ReleaseInstallError.self) { try ReleaseArchive.validate(archive) }
            }
        }
    }

    @Test func unrelatedApplicationIsNeverReplaced() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let version = ReleaseVersion(tag: "v1.2.3-build.4")!
        let applications = root.appendingPathComponent("Applications")
        let old = try signedApp(in: applications, version: version)
        let oldPlist = old.appendingPathComponent("Contents/Info.plist")
        let unrelated = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "app.other"], format: .xml, options: 0)
        try unrelated.write(to: oldPlist)
        let source = try signedApp(in: root.appendingPathComponent("source"), version: version)
        let archive = root.appendingPathComponent("release.zip")
        try tool("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path])
        #expect(throws: ReleaseInstallError.self) {
            try ReleaseInstaller.install(archive: archive, version: version, applications: applications)
        }
        #expect(try Data(contentsOf: oldPlist) == unrelated)
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == ["ClapStudio.app"])
    }

    @Test func aDamagedSignatureKeepsTheInstalledApp() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let version = ReleaseVersion(tag: "v1.2.3-build.4")!
        let applications = root.appendingPathComponent("Applications")
        let old = try signedApp(in: applications, version: version)
        let source = try signedApp(in: root.appendingPathComponent("source"), version: version)
        let executable = source.appendingPathComponent("Contents/MacOS/ClapStudio")
        var damaged = try Data(contentsOf: executable)
        damaged[0] ^= 1
        try damaged.write(to: executable)
        let archive = root.appendingPathComponent("release.zip")
        try tool("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path])
        #expect(throws: (any Error).self) {
            try ReleaseInstaller.install(archive: archive, version: version, applications: applications)
        }
        try ReleaseInstaller.validateBundle(old, version: version)
    }

    @Test func unlistedLocalRecordsAreRefused() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("orphan.zip")
        try zip(path: "ClapStudio.app/file", orphan: true).write(to: archive)
        #expect(throws: ReleaseInstallError.self) { try ReleaseArchive.validate(archive) }
    }

    @Test func actualReleaseBundleCanBeInstalledWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["CLAP_UPDATE_TEST_ARCHIVE"] else { return }
        let version = try #require(ReleaseVersion(tag: ProcessInfo.processInfo.environment["CLAP_UPDATE_TEST_TAG"] ?? ""))
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try ReleaseInstaller.install(archive: URL(fileURLWithPath: path), version: version,
                                                       applications: root.appendingPathComponent("Applications"))
        try ReleaseInstaller.validateBundle(destination, version: version)
    }

    private func signedApp(in parent: URL, version: ReleaseVersion) throws -> URL {
        let app = parent.appendingPathComponent("ClapStudio.app")
        let contents = app.appendingPathComponent("Contents")
        let executables = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executables.appendingPathComponent("ClapStudio"))
        let plist: [String: String] = ["CFBundleIdentifier": ReleaseInstaller.bundleIdentifier,
            "CFBundleExecutable": "ClapStudio", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version.version, "CFBundleVersion": String(version.build)]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try tool("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    private func tool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// A tiny ZIP directory is enough to exercise the paths examined before extraction.
    private func zip(path: String, localPath: String? = nil, mode: UInt32 = 0x8000, duplicate: Bool = false, extra: [UInt8] = [], localExtra: [UInt8]? = nil, orphan: Bool = false) -> Data {
        let name = Array(path.utf8)
        let localName = Array((localPath ?? path).utf8)
        let localPayload = localExtra ?? extra
        var local = [UInt8](repeating: 0, count: 30)
        put(0x04034b50, in: &local, at: 0, count: 4)
        put(UInt32(localName.count), in: &local, at: 26, count: 2)
        put(UInt32(localPayload.count), in: &local, at: 28, count: 2)
        local += localName + localPayload
        var central = [UInt8](repeating: 0, count: 46)
        put(0x02014b50, in: &central, at: 0, count: 4)
        put(UInt32(name.count), in: &central, at: 28, count: 2)
        put(mode << 16, in: &central, at: 38, count: 4)
        put(UInt32(extra.count), in: &central, at: 30, count: 2)
        central += name + extra
        var unlisted: [UInt8] = []
        if orphan {
            unlisted = [UInt8](repeating: 0, count: 30)
            put(0x04034b50, in: &unlisted, at: 0, count: 4)
            let outside = Array("../outside".utf8)
            put(UInt32(outside.count), in: &unlisted, at: 26, count: 2)
            unlisted += outside
            put(UInt32(unlisted.count), in: &central, at: 42, count: 4)
        }
        let directory = duplicate ? central + central : central
        var end = [UInt8](repeating: 0, count: 22)
        put(0x06054b50, in: &end, at: 0, count: 4)
        put(duplicate ? 2 : 1, in: &end, at: 8, count: 2)
        put(duplicate ? 2 : 1, in: &end, at: 10, count: 2)
        put(UInt32(directory.count), in: &end, at: 12, count: 4)
        put(UInt32(unlisted.count + local.count), in: &end, at: 16, count: 4)
        return Data(unlisted + local + directory + end)
    }

    private func put(_ value: UInt32, in data: inout [UInt8], at offset: Int, count: Int) {
        for index in 0..<count { data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
    }
}
