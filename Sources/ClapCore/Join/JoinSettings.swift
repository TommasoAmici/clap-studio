import Foundation

/// Limits for joined files; one cue set marks the start and end of each sound.
public struct JoinSettings: Codable, Equatable, Sendable {
    /// Bounds the memory used to add and verify WAV cue information.
    public static let maximumSeconds = 300.0
    public var maxSeconds: Double
    public var silenceSeconds: Double
    public var maxCuePoints: Int
    public var mono: Bool

    public init(maxSeconds: Double = 11, silenceSeconds: Double = 0.25, maxCuePoints: Int = 64, mono: Bool = true) {
        self.maxSeconds = maxSeconds
        self.silenceSeconds = silenceSeconds
        self.maxCuePoints = maxCuePoints
        self.mono = mono
    }

    public static let almSalmple = JoinSettings()

    public var isValid: Bool {
        return maxSeconds.isFinite && maxSeconds * JoinPlanner.sampleRate >= 1
            && maxSeconds <= Self.maximumSeconds
            && silenceSeconds.isFinite && silenceSeconds >= 0
            && silenceSeconds <= Self.maximumSeconds
            && (1...65_536).contains(maxCuePoints)
    }
}

public enum JoinError: Error, LocalizedError {
    case invalidSettings
    case tooLong(String)
    case tooLarge(String)
    case unsupportedChannels(String)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidSettings: return "Choose a maximum length above zero and up to 300 seconds, silence from 0 to 300 seconds, and 1 to 65,536 cue sets."
        case .tooLong(let name): return "\(name) is longer than the maximum. Trim it in the inspector or raise the maximum."
        case .tooLarge(let name): return "\(name) is too large to join at once. Trim it in the inspector before joining."
        case .unsupportedChannels(let name): return "\(name) has more than two channels. Join mono or stereo samples."
        case .verificationFailed: return "The joined file could not be verified. No source file was changed."
        }
    }
}

/// A sound's exact bounds in a joined file; the silence after it is excluded.
public struct JoinedRegion: Equatable, Sendable {
    public var sourceIndex: Int
    public var startFrame: Int64
    public var endFrame: Int64
}

public struct JoinedFilePlan: Equatable, Sendable {
    public var regions: [JoinedRegion]
    public var frameCount: Int64 { regions.last?.endFrame ?? 0 }
}

public enum JoinPlanner {
    public static let sampleRate = 44_100.0

    public static func plan(frameCounts: [Int64], settings: JoinSettings) throws -> [JoinedFilePlan] {
        guard settings.isValid else { throw JoinError.invalidSettings }
        let maximum = Int64((settings.maxSeconds * sampleRate).rounded(.down))
        let silence = Int64((settings.silenceSeconds * sampleRate).rounded())
        var files: [JoinedFilePlan] = []
        var regions: [JoinedRegion] = []
        for (index, frames) in frameCounts.enumerated() {
            guard frames > 0 else { throw JoinError.invalidSettings }
            guard frames <= maximum else { throw JoinError.tooLong("Sample \(index + 1)") }
            var start = regions.last.map { $0.endFrame + silence } ?? 0
            if !regions.isEmpty, regions.count >= settings.maxCuePoints || start + frames > maximum {
                files.append(JoinedFilePlan(regions: regions))
                regions = []
                start = 0
            }
            regions.append(JoinedRegion(sourceIndex: index, startFrame: start, endFrame: start + frames))
        }
        if !regions.isEmpty { files.append(JoinedFilePlan(regions: regions)) }
        return files
    }
}
