import CryptoKit
import Foundation

public struct ReleaseDownload: Equatable, Sendable {
    public let archiveURL: URL
    public let checksumURL: URL
    public let size: Int64
}

public enum ReleaseInstallError: Error, LocalizedError {
    case missingDownload, downloadFailed, checksumMismatch, invalidArchive, invalidBundle, installFailed
    public var errorDescription: String? {
        switch self {
        case .missingDownload: return "This release does not include an app and its checksum. Open its GitHub release page instead."
        case .downloadFailed: return "The app could not be downloaded from GitHub. Try again later."
        case .checksumMismatch: return "The download did not match the release checksum. The installed app was kept."
        case .invalidArchive: return "The downloaded archive could not be safely opened. The installed app was kept."
        case .invalidBundle: return "The downloaded app did not pass verification. The installed app was kept."
        case .installFailed: return "The update could not be installed in Applications. Try again after checking the folder's permissions."
        }
    }
}

/// Downloads into a private temporary folder and checks the release's SHA-256 before opening its archive.
public enum ReleaseDownloader {
    public static func download(_ update: ReleaseUpdate, into directory: URL) async throws -> URL {
        guard let asset = update.download else { throw ReleaseInstallError.missingDownload }
        var request = URLRequest(url: asset.archiveURL)
        request.timeoutInterval = 600
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              Int64(size) == asset.size else { throw ReleaseInstallError.downloadFailed }
        let archive = directory.appendingPathComponent(asset.archiveURL.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: archive)
        do {
            var checksumRequest = URLRequest(url: asset.checksumURL)
            checksumRequest.timeoutInterval = 30
            let (checksum, checksumResponse) = try await URLSession.shared.data(for: checksumRequest)
            try Task.checkCancellation()
            guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200,
                  checksum.count <= 1024 else { throw ReleaseInstallError.downloadFailed }
            try verify(archive: archive, checksum: checksum, filename: archive.lastPathComponent)
            return archive
        } catch {
            try? FileManager.default.removeItem(at: archive)
            throw error
        }
    }

    public static func verify(archive: URL, checksum: Data, filename: String) throws {
        guard let text = String(data: checksum, encoding: .utf8),
              text.split(separator: "\n", omittingEmptySubsequences: true).count == 1 else {
            throw ReleaseInstallError.checksumMismatch
        }
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0].count == 64,
              parts[0].allSatisfy({ $0.isHexDigit }),
              String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*")) == filename else {
            throw ReleaseInstallError.checksumMismatch
        }
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: bytes)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == parts[0].lowercased() else { throw ReleaseInstallError.checksumMismatch }
    }
}
