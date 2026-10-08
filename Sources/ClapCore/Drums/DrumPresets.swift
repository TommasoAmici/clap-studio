import Foundation

/// A ready-made groove: a tempo, a swing and one or more rhythms for each kind of sound. Sounds are matched to
/// rhythms by their track label (their category), so a preset fits whatever kit is loaded.
public struct DrumPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let bpm: Double
    /// Swing as drum machines show it (50 is straight).
    public let swingPercent: Double
    /// Rhythms per category, written as 16 characters ("x" hits, anything else rests). A second track of the same
    /// category takes the next rhythm in its list, so two hi-hats can play a closed and an open line.
    let rhythms: [String: [String]]

    public var swing: Double { DrumTiming.swing(percent: swingPercent) }

    /// The steps for the nth track (0 for the first) of a category. Empty when the preset has no part for it.
    public func hits(for category: String?, occurrence: Int = 0) -> [Bool] {
        guard let category, let lines = rhythms[Self.role(for: category)], !lines.isEmpty else {
            return Array(repeating: false, count: DrumPattern.stepCount)
        }
        return Self.parse(lines[max(0, occurrence) % lines.count])
    }

    /// Clap and snare share a part: both are the backbeat.
    static func role(for category: String) -> String { category == "Clap" ? "Snare" : category }

    static func parse(_ line: String) -> [Bool] {
        let hits = Array(line).map { $0 == "x" }
        return (0..<DrumPattern.stepCount).map { $0 < hits.count && hits[$0] }
    }

    public static let all: [DrumPreset] = [
        DrumPreset(id: "house", name: "House", bpm: 124, swingPercent: 54, rhythms: [
            "Kick": ["x...x...x...x..."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["..x...x...x...x.", "x.x.x.x.x.x.x.x."],
            "Cymbal": ["x..............."],
            "Percussion": [".x..x..x..x..x..", "...x.......x...x"],
            "Tom": ["..............x."],
        ]),
        DrumPreset(id: "techno", name: "Techno", bpm: 132, swingPercent: 50, rhythms: [
            "Kick": ["x...x...x...x...", "..x...x...x...x."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["..x...x...x...x.", "xxxxxxxxxxxxxxxx"],
            "Cymbal": ["..............x."],
            "Percussion": ["..x..x..x..x..x.", ".x..x..x..x..x.."],
            "Tom": ["...........x...x"],
        ]),
        DrumPreset(id: "dnb", name: "Drum & Bass", bpm: 174, swingPercent: 50, rhythms: [
            "Kick": ["x.........x.....", "..........x....."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["...x..x....x..x.", "..x......x......"],
            "Tom": ["..........x...xx"],
        ]),
        DrumPreset(id: "hiphop", name: "Hip-Hop", bpm: 90, swingPercent: 58, rhythms: [
            "Kick": ["x.....x..x......", "..........x....."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["...x......x....x"],
            "Tom": ["..............x."],
        ]),
        DrumPreset(id: "trap", name: "Trap", bpm: 140, swingPercent: 50, rhythms: [
            "Kick": ["x.........x.....", "..x......x......"],
            "Snare": ["........x......."],
            "Hi-hat": ["x.x.x.x.x.x.xxxx", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["...x......x...x."],
            "Tom": ["..............xx"],
        ]),
        DrumPreset(id: "breakbeat", name: "Breakbeat", bpm: 135, swingPercent: 52, rhythms: [
            "Kick": ["x.....x..x......", "x..x..x........."],
            "Snare": ["....x.......x..x"],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["..x..x....x..x.."],
            "Tom": ["...........x.x.."],
        ]),
        DrumPreset(id: "reggaeton", name: "Reggaeton", bpm: 96, swingPercent: 50, rhythms: [
            "Kick": ["x...x...x...x..."],
            "Snare": ["...x..x....x..x."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["..x...x...x...x."],
            "Tom": ["..............x."],
        ]),
        DrumPreset(id: "electro", name: "Electro", bpm: 128, swingPercent: 50, rhythms: [
            "Kick": ["x.....x...x.....", "x.......x......."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": [".x..x..x..x..x..", "...x..x...x..x.."],
            "Tom": ["..........x.x..."],
        ]),
    ]

    public static func preset(id: String?) -> DrumPreset? { id.flatMap { id in all.first { $0.id == id } } }
}

extension DrumPattern {
    /// Gives every track the rhythm this preset has for its category (a second track of a category takes the next
    /// line, counting clap and snare together) and takes on its swing. Sounds and mixer settings are left alone. The tempo is the project's, so the
    /// caller sets it from `preset.bpm`.
    public mutating func apply(_ preset: DrumPreset) {
        var seen: [String: Int] = [:]
        for index in tracks.indices {
            let label = tracks[index].label
            let role = DrumPreset.role(for: label)
            tracks[index].hits = preset.hits(for: label, occurrence: seen[role, default: 0])
            seen[role, default: 0] += 1
        }
        swing = preset.swing
    }
}
