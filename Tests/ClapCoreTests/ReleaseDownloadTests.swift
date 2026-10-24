import Foundation
import Testing
@testable import ClapCore

@Suite struct ReleaseDownloadTests {
    @Test func downloadableAssetsBelongToTheOfferedRelease() throws {
        let update = try #require(try ReleaseChecker.update(data: release(), statusCode: 200,
            installed: ReleaseVersion(tag: "v0.22.0-build.105")!))
        #expect(update.download?.archiveURL.lastPathComponent == "ClapStudio-0.22.0-build.106-macos.zip")
        #expect(update.download?.checksumURL.lastPathComponent == "ClapStudio-0.22.0-build.106-macos.zip.sha256")
    }

    @Test(arguments: ["https://example.com/app.zip", "http://github.com/TommasoAmici/clap-studio/releases/download/v0.22.0-build.106/ClapStudio-0.22.0-build.106-macos.zip"])
    func assetLinksCannotLeaveTheRelease(url: String) throws {
        #expect(throws: ReleaseCheckError.self) {
            try ReleaseChecker.update(data: release(archiveURL: url), statusCode: 200,
                                      installed: ReleaseVersion(tag: "v0.22.0-build.105")!)
        }
    }

    @Test func releasesWithoutBothAssetsStillOfferTheirReleasePage() throws {
        let update = try #require(try ReleaseChecker.update(data: release(checksum: false), statusCode: 200,
            installed: ReleaseVersion(tag: "v0.22.0-build.105")!))
        #expect(update.download == nil, "older releases can be opened but cannot be installed without their checksum")
    }

    @Test func checksumMustMatchBothTheArchiveAndItsFilename() throws {
        let root = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("app.zip")
        try Data("abc".utf8).write(to: archive)
        let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try ReleaseDownloader.verify(archive: archive, checksum: Data("\(hash)  app.zip\n".utf8), filename: "app.zip")
        #expect(throws: ReleaseInstallError.self) {
            try ReleaseDownloader.verify(archive: archive, checksum: Data("\(hash)  other.zip\n".utf8), filename: "app.zip")
        }
        try Data("changed".utf8).write(to: archive)
        #expect(throws: ReleaseInstallError.self) {
            try ReleaseDownloader.verify(archive: archive, checksum: Data("\(hash)  app.zip\n".utf8), filename: "app.zip")
        }
    }

    private func release(archiveURL: String? = nil, checksum: Bool = true) -> Data {
        let tag = "v0.22.0-build.106"
        let name = "ClapStudio-0.22.0-build.106-macos.zip"
        let prefix = "https://github.com/\(ReleaseChecker.repository)/releases/download/\(tag)/"
        var assets: [[String: Any]] = [["name": name, "browser_download_url": archiveURL ?? prefix + name, "size": 100]]
        if checksum { assets.append(["name": name + ".sha256", "browser_download_url": prefix + name + ".sha256", "size": 110]) }
        return try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": false, "prerelease": false,
            "html_url": "https://github.com/\(ReleaseChecker.repository)/releases/tag/\(tag)", "assets": assets])
    }
}
