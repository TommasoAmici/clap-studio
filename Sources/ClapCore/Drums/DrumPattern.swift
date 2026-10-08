import Foundation

/// One row of the sequencer: a sample and the steps it plays on.
public struct DrumTrack: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var sampleID: Int64
    public var label: String
    public var hits: [Bool]
    public var volume: Float
    public var muted: Bool
    public var solo: Bool
    /// Other samples that fit this slot (from the kit builder), so the sound can be swapped in place.
    public var alternatives: [Int64]

    public init(id: UUID = UUID(), sampleID: Int64, label: String, hits: [Bool] = Array(repeating: false, count: DrumPattern.stepCount),
                volume: Float = 0.9, muted: Bool = false, solo: Bool = false, alternatives: [Int64] = []) {
        self.id = id; self.sampleID = sampleID; self.label = label
        self.hits = hits; self.volume = volume; self.muted = muted; self.solo = solo; self.alternatives = alternatives
    }
}

/// A one-bar, 16-step pattern over a few tracks.
public struct DrumPattern: Equatable, Sendable, Codable {
    public static let stepCount = 16
    public static let maxTracks = 8

    public var tracks: [DrumTrack] = []
    /// How far odd steps are pushed late, as a fraction of a step (0 straight, about 0.33 triplet feel).
    public var swing: Double = 0

    public init(tracks: [DrumTrack] = [], swing: Double = 0) { self.tracks = tracks; self.swing = swing }

    /// What each track is called on screen: its label, numbered ("Kick #1", "Kick #2") when several share it.
    public var displayLabels: [String] {
        let counts = Dictionary(tracks.map { ($0.label, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]
        return tracks.map { track in
            guard counts[track.label, default: 0] > 1 else { return track.label }
            seen[track.label, default: 0] += 1
            return "\(track.label) #\(seen[track.label]!)"
        }
    }

    /// What was saved, made safe to play: every track has exactly one bar of steps, a volume in range, and there are
    /// no more tracks than fit.
    public func sanitized() -> DrumPattern {
        var copy = self
        copy.tracks = Array(tracks.prefix(Self.maxTracks)).map { track in
            var t = track
            t.hits = (0..<Self.stepCount).map { track.hits.indices.contains($0) && track.hits[$0] }
            t.volume = min(max(track.volume.isFinite ? track.volume : 0.9, 0), 1)
            return t
        }
        copy.swing = min(max(swing.isFinite ? swing : 0, -0.5), 0.5)
        return copy
    }

    public var isFull: Bool { tracks.count >= Self.maxTracks }

    public mutating func toggle(track: Int, step: Int) {
        guard tracks.indices.contains(track), (0..<Self.stepCount).contains(step) else { return }
        tracks[track].hits[step].toggle()
    }

    /// Adds a track (at the end, or at `index`) unless the pattern is full. A rhythm for its category is filled in when `starter` is set: the
    /// preset's, or a plain one without a preset.
    @discardableResult
    public mutating func addTrack(sampleID: Int64, label: String, category: String?, alternatives: [Int64] = [],
                                  starter: Bool = true, preset: DrumPreset? = nil, at index: Int? = nil) -> Bool {
        guard !isFull else { return false }
        var hits = Array(repeating: false, count: Self.stepCount)
        if starter {
            if let preset {
                let role = DrumPreset.role(for: label)
                hits = preset.hits(for: label, occurrence: tracks.filter { DrumPreset.role(for: $0.label) == role }.count)
            } else {
                hits = DrumStarter.hits(for: category)
            }
        }
        let track = DrumTrack(sampleID: sampleID, label: label, hits: hits, alternatives: alternatives)
        tracks.insert(track, at: min(max(index ?? tracks.count, 0), tracks.count))
        return true
    }

    /// Swaps the sound on a track and keeps the rhythm.
    public mutating func replaceSample(track: Int, with sampleID: Int64) {
        guard tracks.indices.contains(track) else { return }
        tracks[track].sampleID = sampleID
    }

    public mutating func clearHits() {
        for i in tracks.indices { tracks[i].hits = Array(repeating: false, count: Self.stepCount) }
    }

    public mutating func removeTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        tracks.remove(at: index)
    }
}

/// Simple rhythms to start from, so a kit makes a beat the moment it loads.
public enum DrumStarter {
    public static func hits(for category: String?) -> [Bool] {
        let steps: [Int]
        switch category {
        case "Kick": steps = [0, 4, 8, 12]
        case "Snare", "Rimshot", "Clap": steps = [4, 12]
        case "Hi-hat": steps = [0, 2, 4, 6, 8, 10, 12, 14]
        case "Cymbal": steps = [0]
        case "Tom": steps = [10, 14]
        case "Percussion": steps = [3, 7, 11, 15]
        case "Cowbell": steps = [2, 6, 10, 14]
        default: steps = []
        }
        return (0..<DrumPattern.stepCount).map { steps.contains($0) }
    }
}

/// What dropping a sound at a height over the track list does.
public enum DrumDropTarget: Equatable, Sendable {
    /// The sound takes over this track.
    case replace(Int)
    /// A new track goes in at this position (0 is above the first track, the track count is below the last).
    case insert(Int)

    /// The middle of a row replaces it; the edges of a row, the gaps between rows and everything above or below
    /// the list insert at the nearest boundary, so the drop never needs to be aimed precisely.
    /// `rows` are the rows' vertical extents, top to bottom.
    public static func resolve(y: Double, rows: [ClosedRange<Double>], edge: Double = 0.28) -> DrumDropTarget {
        if let index = rows.firstIndex(where: { $0.contains(y) }) {
            let row = rows[index], margin = (row.upperBound - row.lowerBound) * edge
            if y >= row.lowerBound + margin && y <= row.upperBound - margin { return .replace(index) }
        }
        return .insert(rows.filter { ($0.lowerBound + $0.upperBound) / 2 < y }.count)
    }
}
