import Foundation

/// One row of the sequencer: a sample and the steps it plays on.
public struct DrumTrack: Identifiable, Equatable, Sendable {
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
public struct DrumPattern: Equatable, Sendable {
    public static let stepCount = 16
    public static let maxTracks = 8

    public var tracks: [DrumTrack] = []
    /// How far odd steps are pushed late, as a fraction of a step (0 straight, about 0.33 triplet feel).
    public var swing: Double = 0

    public init(tracks: [DrumTrack] = [], swing: Double = 0) { self.tracks = tracks; self.swing = swing }

    public var isFull: Bool { tracks.count >= Self.maxTracks }

    public mutating func toggle(track: Int, step: Int) {
        guard tracks.indices.contains(track), (0..<Self.stepCount).contains(step) else { return }
        tracks[track].hits[step].toggle()
    }

    /// Adds a track unless the pattern is full. A starter rhythm for its category is filled in when `starter` is set.
    @discardableResult
    public mutating func addTrack(sampleID: Int64, label: String, category: String?, alternatives: [Int64] = [], starter: Bool = true) -> Bool {
        guard !isFull else { return false }
        tracks.append(DrumTrack(sampleID: sampleID, label: label, hits: starter ? DrumStarter.hits(for: category) : Array(repeating: false, count: Self.stepCount),
                                alternatives: alternatives))
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
        case "Snare", "Clap": steps = [4, 12]
        case "Hi-hat": steps = [0, 2, 4, 6, 8, 10, 12, 14]
        case "Cymbal": steps = [0]
        case "Tom": steps = [10, 14]
        case "Percussion": steps = [3, 7, 11, 15]
        default: steps = []
        }
        return (0..<DrumPattern.stepCount).map { steps.contains($0) }
    }
}
