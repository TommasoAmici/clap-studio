import Foundation

public enum SampleStatus: String, Sendable {
    case pending, ok, failed, missing
}

public struct RootRecord: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let path: String
}

public struct SampleRecord: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let rootID: Int64
    public let rootPath: String
    public let relPath: String
    public let name: String
    public let ext: String
    public var duration: Double
    public var sampleRate: Double
    public var channels: Int
    public var size: Int64
    public var mtime: Double
    public var status: SampleStatus
    public var useCount: Int
    public var lastUsed: Double?
    public var cueCount: Int

    public var url: URL { URL(fileURLWithPath: rootPath).appendingPathComponent(relPath) }

    /// Folder relative to the root ("" for files directly in the root).
    public var folder: String {
        let dir = (relPath as NSString).deletingLastPathComponent
        return dir == "." ? "" : dir
    }
}

public struct ScannedFile: Hashable, Sendable {
    public let relPath: String
    public let size: Int64
    public let mtime: Double
    public init(relPath: String, size: Int64, mtime: Double) {
        self.relPath = relPath
        self.size = size
        self.mtime = mtime
    }
}

public struct SyncResult: Equatable, Sendable {
    public var added = 0
    public var changed = 0
    public var moved = 0
    public var missing = 0
    public var unchanged = 0
}

public struct IndexJob: Sendable {
    public let id: Int64
    public let url: URL
}

public enum IndexResult: Sendable {
    case success(id: Int64, duration: Double, sampleRate: Double, channels: Int,
                 embedding: [Float], fingerprint: String?, modelVersion: String, cues: [FileCue] = [])
    case failure(id: Int64, message: String)
}

public enum CueSource: String, Sendable {
    case file, user
}

public struct CuePoint: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var sampleID: Int64
    public var positionFrames: Int64
    public var label: String
    public var source: CueSource
    public var fileSynced: Bool
}
