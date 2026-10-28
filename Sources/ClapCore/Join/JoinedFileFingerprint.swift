import CryptoKit
import Darwin
import Foundation

/// A full-file digest for checking that a joined output still contains its original audio.
public enum JoinedFileFingerprint {
    struct Identity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64

        init(_ info: stat) {
            device = UInt64(UInt32(bitPattern: info.st_dev))
            inode = UInt64(info.st_ino)
            size = info.st_size
            modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        }

        var modified: Double { Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000 }
    }

    struct Snapshot: Equatable, Sendable {
        let digest: String
        let identity: Identity

        func isCurrent(at url: URL, scanned: ScannedFile? = nil) -> Bool {
            guard JoinedFileFingerprint.identity(at: url) == identity else { return false }
            guard let scanned else { return true }
            return identity.size == scanned.size && abs(identity.modified - scanned.mtime) < 0.000_001
        }
    }

    public static func compute(url: URL) -> String? { snapshot(url: url)?.digest }

    static func snapshot(url: URL, isCancelled: () -> Bool = { false }, onChunk: (() -> Void)? = nil) -> Snapshot? {
        do {
            guard let before = identity(at: url) else { return nil }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard identity(of: handle) == before else { return nil }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                guard !Task.isCancelled, !isCancelled() else { return nil }
                hasher.update(data: chunk)
                onChunk?()
            }
            guard !Task.isCancelled, !isCancelled(), identity(of: handle) == before, identity(at: url) == before else { return nil }
            return Snapshot(digest: hasher.finalize().map { String(format: "%02x", $0) }.joined(), identity: before)
        } catch { return nil }
    }

    private static func identity(at url: URL) -> Identity? {
        var info = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return fstatat(AT_FDCWD, path, &info, 0)
        }
        return result == 0 ? Identity(info) : nil
    }

    private static func identity(of handle: FileHandle) -> Identity? {
        var info = stat()
        return fstat(handle.fileDescriptor, &info) == 0 ? Identity(info) : nil
    }
}
