import Foundation

public enum SampleStatus: String, Sendable {
    case pending, ok, failed, missing
}

public struct RootRecord: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let path: String
    /// True for a temporary root such as a USB stick: not part of the library proper and never kept between runs.
    public var isTransient = false
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

    // Measured and derived properties (nil until analysed).
    public var loudnessDB: Double? = nil
    public var peakDB: Double? = nil
    public var crestDB: Double? = nil
    public var centroidHz: Double? = nil
    public var isLoop: Bool? = nil
    public var bpm: Double? = nil
    public var bpmManual: Double? = nil
    public var pitchHz: Double? = nil
    public var keyName: String? = nil
    public var category: String? = nil
    public var categoryManual: String? = nil
    public var favorite: Bool = false
    public var hidden: Bool = false
    /// The user's own labels, sorted.
    public var tags: [String] = []
    /// The moods that count, in the sidebar's order: the user's own when they set any, else the automatic ones.
    public var moods: [String] = []
    /// What the library's analysis found, kept so the user can go back to it.
    public var moodsAuto: [String] = []
    /// The user's own moods (empty: they chose none); nil while the automatic ones are used.
    public var moodsManual: [String]? = nil
    /// What the segments of a field recording sound like (birds, water, ...), in the sidebar's order.
    public var sounds: [String] = []

    /// The user's BPM correction wins over the detected one.
    /// Long recordings are analysed in segments (see `FieldRecording`).
    /// Long files, and any file the user has put in the Field recording category.
    public var isFieldRecording: Bool { FieldRecording.isFieldRecording(duration: duration, manualCategory: categoryManual) }

    public var effectiveBPM: Double? { bpmManual ?? bpm }
    public var effectiveCategory: String? { categoryManual ?? category }

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
    /// The user put this file in the Field recording category, so it is segmented whatever its length.
    public var isFieldRecording = false
}

/// One audible stretch of a field recording and its embedding.
public struct SegmentEmbedding: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var embedding: [Float]
    public init(start: Double, end: Double, embedding: [Float]) {
        self.start = start; self.end = end; self.embedding = embedding
    }
    public var length: Double { end - start }
}

/// The part of a field recording that best matches a query.
public struct SegmentMatch: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var score: Float
    public init(start: Double, end: Double, score: Float) { self.start = start; self.end = end; self.score = score }
}

public enum IndexResult: Sendable {
    case success(id: Int64, duration: Double, sampleRate: Double, channels: Int,
                 embedding: [Float], fingerprint: String?, modelVersion: String, cues: [FileCue] = [],
                 descriptors: SoundDescriptors? = nil, segments: [SegmentEmbedding] = [])
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
