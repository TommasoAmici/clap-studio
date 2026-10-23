import Foundation

/// A release's version and build number, including the builds published between version bumps.
public struct ReleaseVersion: Comparable, Equatable, Sendable {
    public let version: String
    public let build: Int
    private let numbers: [Int]

    public init?(version: String?, build: String?) {
        guard let version, let build, let buildNumber = Self.number(build),
              let numbers = Self.versionNumbers(version) else { return nil }
        self.version = version
        self.build = buildNumber
        self.numbers = numbers
    }

    public init?(tag: String) {
        let text = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = text.components(separatedBy: "-build.")
        guard parts.count <= 2 else { return nil }
        self.init(version: parts[0], build: parts.count == 2 ? parts[1] : "0")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        return lhs.build < rhs.build
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.numbers == rhs.numbers && lhs.build == rhs.build
    }

    private static func versionNumbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { number(String($0)) }
        return numbers.count == 3 ? numbers : nil
    }

    private static func number(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(text)
    }
}

public struct ReleaseUpdate: Equatable, Sendable {
    public let tag: String
    public let version: ReleaseVersion
    public let pageURL: URL
}

public enum ReleaseCheckError: Error, LocalizedError {
    case requestFailed, invalidRelease, noPublicRelease
    public var errorDescription: String? {
        switch self {
        case .requestFailed: return "GitHub could not be reached. Try again later."
        case .invalidRelease: return "GitHub returned release details that could not be read."
        case .noPublicRelease: return "No public Clap Studio release is available on GitHub."
        }
    }
}

/// Checks only public release details; the app never sends the user's samples or library.
public enum ReleaseChecker {
    public static let repository = "TommasoAmici/clap-studio"
    public static let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    public static func latest(installed: ReleaseVersion) async throws -> ReleaseUpdate? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ClapStudio/\(installed.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ReleaseCheckError.requestFailed }
        return try update(data: data, statusCode: http.statusCode, installed: installed)
    }

    public static func update(data: Data, statusCode: Int, installed: ReleaseVersion) throws -> ReleaseUpdate? {
        if statusCode == 404 { throw ReleaseCheckError.noPublicRelease }
        guard statusCode == 200 else { throw ReleaseCheckError.requestFailed }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { throw ReleaseCheckError.invalidRelease }
        guard !release.draft, !release.prerelease, let version = ReleaseVersion(tag: release.tag),
              version > installed else { return nil }
        // Opening a browser is limited to this release's own page, even for malformed server responses.
        let expected = "https://github.com/\(repository)/releases/tag/\(release.tag)"
        guard release.page == expected, let page = URL(string: expected) else { throw ReleaseCheckError.invalidRelease }
        return ReleaseUpdate(tag: release.tag, version: version, pageURL: page)
    }

    private struct GitHubRelease: Decodable {
        let tag: String
        let page: String
        let draft: Bool
        let prerelease: Bool
        enum CodingKeys: String, CodingKey {
            case tag = "tag_name", page = "html_url", draft, prerelease
        }
    }
}

public enum UpdateSchedule {
    public static func shouldCheck(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= 86_400 || elapsed < 0
    }
}
