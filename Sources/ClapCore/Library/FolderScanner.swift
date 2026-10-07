import CryptoKit
import Foundation

/// Read-only enumeration of audio files below a root folder.
public enum FolderScanner {
    public static let supportedExtensions: Set<String> =
        ["wav", "wave", "aif", "aiff", "aifc", "mp3", "flac", "m4a", "aac", "caf"]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Returns every supported audio file below `root`. Never writes to disk.
    public static func scan(root: URL, isCancelled: () -> Bool = { false }) -> [ScannedFile] {
        let resolved = URL(fileURLWithPath: realPath(root.path))
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: resolved, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        let prefix = resolved.path.hasSuffix("/") ? resolved.path : resolved.path + "/"
        var files: [ScannedFile] = []
        for case let url as URL in walker {
            if isCancelled() { break }
            guard isSupported(url),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let path = url.path
            guard path.hasPrefix(prefix) else { continue }
            files.append(ScannedFile(
                relPath: String(path.dropFirst(prefix.count)),
                size: Int64(values.fileSize ?? 0),
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        return files
    }
}

/// Fully resolved path (unlike `resolvingSymlinksInPath`, keeps /private/var intact).
func realPath(_ path: String) -> String {
    guard let p = realpath(path, nil) else { return path }
    defer { free(p) }
    return String(cString: p)
}

/// Cheap content fingerprint (size + head + tail bytes) used to follow files
/// that were moved or renamed so embeddings and usage counts survive.
public enum FileFingerprint {
    private static let window = 4096

    public static func compute(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        try? handle.seek(toOffset: 0)
        if let head = try? handle.read(upToCount: window) { hasher.update(data: head) }
        if size > UInt64(window) {
            try? handle.seek(toOffset: size - UInt64(window))
            if let tail = try? handle.read(upToCount: window) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
