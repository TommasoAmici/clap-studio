import Foundation
import Testing
@testable import ClapCore

@Suite struct ReleaseUpdateTests {
    @Test func newerBuildsOfTheSameVersionAreUpdates() throws {
        let installed = try #require(ReleaseVersion(version: "0.22.0", build: "105"))
        #expect(ReleaseVersion(tag: "v0.22.0-build.106")! > installed,
                "every main push publishes a release even without a marketing version bump")
        #expect(ReleaseVersion(tag: "v0.22.0-build.105") == installed)
        #expect(ReleaseVersion(tag: "v0.22.0-build.104")! < installed)
        #expect(ReleaseVersion(tag: "v0.23.0-build.1")! > installed)
        #expect(ReleaseVersion(tag: "v0.21.9-build.999")! < installed)
    }

    @Test func versionNumbersAreComparedAsNumbers() throws {
        let installed = try #require(ReleaseVersion(version: "0.9.9", build: "9"))
        #expect(ReleaseVersion(tag: "v0.10.0-build.10")! > installed)
        #expect(ReleaseVersion(tag: "v1.0.0")! > installed,
                "plain stable tags are supported alongside workflow build tags")
    }

    @Test(arguments: ["v1.2", "v1.2.3-beta.1", "v1.2.3-build.x", "v-1.2.3", "v1.2.3.4", "v1.2.3-build.-1", "v1.2.3-build.999999999999999999999", ""])
    func malformedOrPrereleaseTagsAreIgnored(tag: String) {
        #expect(ReleaseVersion(tag: tag) == nil)
    }

    @Test func missingBundleVersionIsNotInvented() {
        #expect(ReleaseVersion(version: nil, build: "1") == nil)
        #expect(ReleaseVersion(version: "1.2.3", build: nil) == nil)
        #expect(ReleaseVersion(version: "1.2.3", build: "invalid") == nil)
    }

    @Test func onlyNewerPublishedReleasesPrompt() throws {
        let installed = try #require(ReleaseVersion(version: "0.22.0", build: "105"))
        let newer = try ReleaseChecker.update(data: release(), statusCode: 200, installed: installed)
        #expect(newer?.version == ReleaseVersion(tag: "v0.22.0-build.106"))
        #expect(newer?.pageURL.absoluteString == "https://github.com/TommasoAmici/clap-studio/releases/tag/v0.22.0-build.106")
        #expect(try ReleaseChecker.update(data: release(tag: "v0.22.0-build.105"), statusCode: 200, installed: installed) == nil)
        #expect(try ReleaseChecker.update(data: release(draft: true), statusCode: 200, installed: installed) == nil)
        #expect(try ReleaseChecker.update(data: release(prerelease: true), statusCode: 200, installed: installed) == nil)
        #expect(throws: ReleaseCheckError.self) {
            try ReleaseChecker.update(data: Data(), statusCode: 404, installed: installed)
        }
    }

    @Test(arguments: ["http://github.com/TommasoAmici/clap-studio/releases/tag/v0.22.0-build.106",
                       "https://example.com/update", "https://github.com/Other/project/releases/tag/v0.22.0-build.106",
                       "https://github.com/TommasoAmici/clap-studio/releases/tag/v9.0.0-build.106"])
    func releaseLinksStayInThisRepository(url: String) throws {
        let installed = try #require(ReleaseVersion(version: "0.22.0", build: "105"))
        #expect(throws: ReleaseCheckError.self) {
            try ReleaseChecker.update(data: release(url: url), statusCode: 200, installed: installed)
        }
    }

    @Test func failedRequestsAndInvalidJSONAreErrors() throws {
        let installed = try #require(ReleaseVersion(version: "0.22.0", build: "105"))
        #expect(throws: ReleaseCheckError.self) {
            try ReleaseChecker.update(data: release(), statusCode: 403, installed: installed)
        }
        #expect(throws: (any Error).self) {
            try ReleaseChecker.update(data: Data("not json".utf8), statusCode: 200, installed: installed)
        }
    }

    @Test func automaticChecksAreAtMostDailyButRecoverFromClockChanges() {
        let now = Date(timeIntervalSince1970: 200_000)
        #expect(UpdateSchedule.shouldCheck(now: now, lastCheck: nil))
        #expect(!UpdateSchedule.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-3600)))
        #expect(UpdateSchedule.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-86_400)))
        #expect(UpdateSchedule.shouldCheck(now: now, lastCheck: now.addingTimeInterval(3600)),
                "a clock moved backwards cannot postpone update checks indefinitely")
    }

    @Test func launchingChecksEvenWhenTheLastCheckWasRecent() {
        let now = Date(timeIntervalSince1970: 200_000)
        #expect(UpdateSchedule.shouldCheck(now: now, lastCheck: now, onLaunch: true),
                "opening the app should find a release published since the last session")
        #expect(!UpdateSchedule.shouldCheck(now: now, lastCheck: now, onLaunch: false))
    }

    private func release(tag: String = "v0.22.0-build.106", draft: Bool = false,
                         prerelease: Bool = false, url: String? = nil) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": url ?? "https://github.com/TommasoAmici/clap-studio/releases/tag/\(tag)"])
    }
}
