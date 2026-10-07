import CoreServices
import Foundation

/// Reports when audio files appear, change, move or vanish below the watched folders.
/// Changes are coalesced by the system over `latency` seconds, so a big copy gives a few callbacks, not thousands.
public final class FolderWatcher: @unchecked Sendable {
    private let paths: [String]
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "clap.watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private lazy var roots: Set<String> = Set(paths.map { Self.realPath($0) })

    public init(paths: [String], latency: TimeInterval = 2, onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            let flags = UnsafeBufferPointer(start: eventFlags, count: count)
            watcher.handle(paths: paths, flags: Array(flags))
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        // The watched folders themselves changing (for example being created) says nothing about their contents.
        let kept = zip(paths, flags).filter { !roots.contains($0.0) }
        if Self.isRelevant(paths: kept.map(\.0), flags: kept.map(\.1)) { onChange() }
    }

    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Audio files, and folders that were added, moved or removed (they may hold audio).
    static func isRelevant(paths: [String], flags: [FSEventStreamEventFlags]) -> Bool {
        for (path, flag) in zip(paths, flags) {
            let structural = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                                                     | kFSEventStreamEventFlagItemRenamed)
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0, flag & structural != 0 { return true }
            if FolderScanner.isSupported(URL(fileURLWithPath: path)) { return true }
        }
        return false
    }
}
