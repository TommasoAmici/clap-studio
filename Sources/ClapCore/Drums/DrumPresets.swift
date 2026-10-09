import Foundation

/// A ready-made groove: a tempo, a swing and one or more rhythms for each kind of sound. Sounds are matched to
/// rhythms by their track label (their category), so a preset fits whatever kit is loaded.
public struct DrumPreset: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var name: String
    public let bpm: Double
    /// Swing as drum machines show it (50 is straight).
    public let swingPercent: Double
    /// Rhythms per category, written as 16 characters ("x" hits, anything else rests). A second track of the same
    /// category takes the next rhythm in its list, so two hi-hats can play a closed and an open line.
    let rhythms: [String: [String]]
    /// True for grooves the user saved, as opposed to the ones shipped with the app.
    public var isUser = false

    public var swing: Double { DrumTiming.swing(percent: swingPercent) }

    /// The steps for the nth track (0 for the first) of a category. Empty when the preset has no part for it.
    public func hits(for category: String?, occurrence: Int = 0) -> [Bool] {
        let silence = Array(repeating: false, count: DrumPattern.stepCount)
        guard let category else { return silence }
        let role = Self.role(for: category)
        if let lines = rhythms[role], !lines.isEmpty { return Self.parse(lines[max(0, occurrence) % lines.count]) }
        // The shipped grooves play every other kind of sound too (a bass, a vocal, an ambience); a groove the user
        // saved keeps to the parts it was saved with.
        if !isUser, let line = Self.accompaniment(for: role) { return Self.parse(line) }
        return silence
    }

    /// A simple part for sounds that are not drum-kit pieces, so any sample dropped into the drum machine plays
    /// something with a built-in groove: bass and chord-like sounds get a few hits, everything else (pads, effects,
    /// vocals, field sounds, loops) is triggered once per bar. nil for the categories the grooves write themselves.
    static func accompaniment(for role: String) -> String? {
        if drumRoles.contains(role) { return nil }
        switch role {
        case "Bass": return "x..x..x...x..x.."
        case "Pluck": return "x..x..x...x.x..."
        case "Synth", "Keys", "Guitar": return "x.....x.....x..."
        case "Lead", "Brass & Winds", "Bells": return "x.......x......."
        default: return "x..............."
        }
    }

    /// The categories each groove writes a rhythm for itself.
    static let drumRoles: Set<String> = ["Kick", "Snare", "Rimshot", "Hi-hat", "Cymbal", "Tom", "Percussion", "Cowbell"]

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
            "Rimshot": ["..x.......x....."],
            "Cowbell": ["x..x..x...x..x.."],
        ]),
        DrumPreset(id: "techno", name: "Techno", bpm: 132, swingPercent: 50, rhythms: [
            "Kick": ["x...x...x...x...", "..x...x...x...x."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["..x...x...x...x.", "xxxxxxxxxxxxxxxx"],
            "Cymbal": ["..............x."],
            "Percussion": ["..x..x..x..x..x.", ".x..x..x..x..x.."],
            "Tom": ["...........x...x"],
            "Rimshot": ["...x......x....x"],
            "Cowbell": ["..x...x...x...x."],
        ]),
        DrumPreset(id: "dnb", name: "Drum & Bass", bpm: 174, swingPercent: 50, rhythms: [
            "Kick": ["x.........x.....", "..........x....."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["...x..x....x..x.", "..x......x......"],
            "Tom": ["..........x...xx"],
            "Rimshot": ["...x.......x...."],
            "Cowbell": ["x..x..x.x......."],
        ]),
        DrumPreset(id: "hiphop", name: "Hip-Hop", bpm: 90, swingPercent: 58, rhythms: [
            "Kick": ["x.....x..x......", "..........x....."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["...x......x....x"],
            "Tom": ["..............x."],
            "Rimshot": ["..x......x......"],
            "Cowbell": ["x..x......x.x..."],
        ]),
        DrumPreset(id: "trap", name: "Trap", bpm: 140, swingPercent: 50, rhythms: [
            "Kick": ["x.........x.....", "..x......x......"],
            "Snare": ["........x......."],
            "Hi-hat": ["x.x.x.x.x.x.xxxx", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["...x......x...x."],
            "Tom": ["..............xx"],
            "Rimshot": ["...x......x....x"],
            "Cowbell": ["x..x..x.x..x..x."],
        ]),
        DrumPreset(id: "breakbeat", name: "Breakbeat", bpm: 135, swingPercent: 52, rhythms: [
            "Kick": ["x.....x..x......", "x..x..x........."],
            "Snare": ["....x.......x..x"],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["..x..x....x..x.."],
            "Tom": ["...........x.x.."],
            "Rimshot": ["..x.......x..x.."],
            "Cowbell": ["x..x..x...x....."],
        ]),
        DrumPreset(id: "reggaeton", name: "Reggaeton", bpm: 96, swingPercent: 50, rhythms: [
            "Kick": ["x...x...x...x..."],
            "Snare": ["...x..x....x..x."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": ["..x...x...x...x."],
            "Tom": ["..............x."],
            "Rimshot": [".x..x..x.x..x..."],
            "Cowbell": ["x..x..x.x..x..x."],
        ]),
        DrumPreset(id: "electro", name: "Electro", bpm: 128, swingPercent: 50, rhythms: [
            "Kick": ["x.....x...x.....", "x.......x......."],
            "Snare": ["....x.......x..."],
            "Hi-hat": ["x.x.x.x.x.x.x.x.", "..x...x...x...x."],
            "Cymbal": ["x..............."],
            "Percussion": [".x..x..x..x..x..", "...x..x...x..x.."],
            "Tom": ["..........x.x..."],
            "Rimshot": ["..x..x....x....."],
            "Cowbell": ["x..x..x...x..x.."],
        ]),
    ]

    public static let maxNameLength = 40

    /// Looks a groove up among the built-in ones and, when given, the user's own.
    public static func preset(id: String?, among user: [DrumPreset] = []) -> DrumPreset? {
        guard let id else { return nil }
        return (all + user).first { $0.id == id }
    }

    /// A name fit for a menu: trimmed, one line, not too long. nil when nothing is left.
    public static func cleanName(_ raw: String) -> String? {
        let name = raw.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name.prefix(maxNameLength))
    }
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

extension DrumPattern {
    /// Captures this pattern's rhythms (per category, in track order), swing and the given tempo as a groove that can
    /// be applied to any kit later. Returns nil for an unusable name or when no track has a step.
    public func makePreset(name: String, id: String = "user." + UUID().uuidString, bpm: Double) -> DrumPreset? {
        guard let name = DrumPreset.cleanName(name), tracks.contains(where: { $0.hits.contains(true) }) else { return nil }
        var rhythms: [String: [String]] = [:]
        for track in tracks {
            let line = String((0..<Self.stepCount).map { track.hits.indices.contains($0) && track.hits[$0] ? "x" : "." })
            rhythms[DrumPreset.role(for: track.label), default: []].append(line)
        }
        return DrumPreset(id: id, name: name, bpm: min(max(bpm, 20), 300), swingPercent: DrumTiming.swingPercent(swing),
                          rhythms: rhythms, isUser: true)
    }
}
