import Foundation

/// A note read from a MIDI file, placed on the same grid as `MelodyNote`: steps are sixteenth notes.
public struct MidiNote: Equatable, Sendable {
    public var pitch: Int
    public var start: Double
    public var length: Double
    public var velocity: Float
    public init(pitch: Int, start: Double, length: Double, velocity: Float) {
        self.pitch = pitch; self.start = start; self.length = length; self.velocity = velocity
    }
}

/// The notes of one MIDI track (or, for a single-track file, of one channel), sorted by start.
public struct MidiTrack: Equatable, Sendable {
    public var name: String
    public var notes: [MidiNote]
    public init(name: String, notes: [MidiNote]) { self.name = name; self.notes = notes }
    /// Where the last note ends, in steps.
    public var endStep: Double { notes.map { $0.start + $0.length }.max() ?? 0 }
}

/// What is read from a MIDI file: its notes by track, and the tempo it asks for, if it names one.
public struct MidiSong: Equatable, Sendable {
    public var tracks: [MidiTrack]
    /// Beats per minute from the first tempo in the file, held to the range the drum machine can keep; nil when it has none.
    public var bpm: Double?
    public init(tracks: [MidiTrack], bpm: Double? = nil) { self.tracks = tracks; self.bpm = bpm }
}

public enum MidiError: Error, Equatable, LocalizedError {
    case notMidi, unsupportedTiming, tooLarge

    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "This MIDI file is too large to open here."
        case .notMidi: return "This is not a MIDI file Clap Studio can read."
        case .unsupportedTiming: return "This MIDI file keeps time in frames rather than beats, which Clap Studio cannot place on a grid."
        }
    }
}

/// Reads Standard MIDI Files (formats 0 and 1) for their notes and their tempo. Time signature, controllers and
/// everything else are skipped: the notes are placed by beats, so they follow the project tempo (which the file's
/// own tempo can set, if the user wants).
public enum MidiFile {
    /// Real songs are a few hundred kilobytes; anything far beyond this is not a song and is not read.
    public static let maxBytes = 32 * 1024 * 1024

    /// The tempo range the drum machine can keep, in beats per minute.
    public static let tempoRange = 30.0...300.0

    public static func read(url: URL, maxBytes: Int = MidiFile.maxBytes) throws -> [MidiTrack] {
        try readSong(url: url, maxBytes: maxBytes).tracks
    }

    public static func readSong(url: URL, maxBytes: Int = MidiFile.maxBytes, splitChannels: Bool = true) throws -> MidiSong {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxBytes else { throw MidiError.tooLarge }
        return try parseSong(Data(contentsOf: url), splitChannels: splitChannels)
    }

    /// True for a file named like a MIDI file (.mid or .midi, in any case).
    public static func isMidiFile(_ url: URL) -> Bool { ["mid", "midi"].contains(url.pathExtension.lowercased()) }

    /// A file that is cut off or damaged part way keeps the notes read before the damage.
    public static func parse(_ data: Data) throws -> [MidiTrack] { try parseSong(data).tracks }

    /// Set `splitChannels` to false to keep format-zero files as one physical track, as the drum grid does.
    public static func parseSong(_ data: Data, splitChannels: Bool = true) throws -> MidiSong {
        var reader = ByteReader(Array(data))
        guard reader.take(4) == Array("MThd".utf8), let headerLength = reader.u32(), headerLength >= 6,
              let format = reader.u16(), reader.u16() != nil, let division = reader.u16() else { throw MidiError.notMidi }
        guard division & 0x8000 == 0, division > 0 else { throw MidiError.unsupportedTiming }
        reader.skip(Int(headerLength) - 6)
        let stepsPerTick = 4 / Double(division)

        var tracks: [MidiTrack] = []
        var firstTempo: (tick: Int, micros: Int)?
        while let id = reader.take(4), let length = reader.u32() {
            let body = reader.take(Int(length)) ?? reader.rest()          // a short last chunk is read as far as it goes
            guard id == Array("MTrk".utf8) else { continue }
            let (name, notes, tempo) = readTrack(body, stepsPerTick: stepsPerTick)
            if let tempo, firstTempo == nil || tempo.tick < firstTempo!.tick { firstTempo = tempo }
            guard !notes.isEmpty else { continue }
            if format == 0 && splitChannels {
                let channels = Dictionary(grouping: notes, by: \.channel)
                for channel in channels.keys.sorted() {
                    tracks.append(MidiTrack(name: "Channel \(channel + 1)", notes: sorted(channels[channel]!.map(\.note))))
                }
            } else {
                tracks.append(MidiTrack(name: name, notes: sorted(notes.map(\.note))))
            }
        }
        let bpm = firstTempo.map { 60_000_000 / Double($0.micros) }.map { min(max(($0 * 10).rounded() / 10, tempoRange.lowerBound), tempoRange.upperBound) }
        return MidiSong(tracks: tracks, bpm: bpm)
    }

    private static func sorted(_ notes: [MidiNote]) -> [MidiNote] {
        notes.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    private struct Played { var channel: Int; var note: MidiNote }

    private static func readTrack(_ bytes: [UInt8], stepsPerTick: Double) -> (name: String, notes: [Played], tempo: (tick: Int, micros: Int)?) {
        var reader = ByteReader(bytes)
        var name = ""
        var tempo: (tick: Int, micros: Int)?
        var tick = 0
        var status: UInt8 = 0
        var open: [Int: [(tick: Int, velocity: Float)]] = [:]       // by channel * 128 + pitch; oldest first
        var notes: [Played] = []

        func close(_ key: Int, at end: Int) {
            guard var starts = open[key], !starts.isEmpty else { return }
            let began = starts.removeFirst()
            open[key] = starts
            let length = max(MelodyNote.minLength, Double(end - began.tick) * stepsPerTick)
            notes.append(Played(channel: key / 128, note: MidiNote(pitch: key % 128, start: Double(began.tick) * stepsPerTick,
                                                                   length: length, velocity: began.velocity)))
        }

        loop: while let delta = reader.variableLength() {
            tick += delta
            guard var first = reader.peek() else { break }
            if first >= 0x80 { status = first; reader.skip(1) } else if status == 0 { break } else { first = status }
            switch first {
            case 0xFF:
                status = 0
                guard let type = reader.u8(), let length = reader.variableLength(), let data = reader.take(length) else { break loop }
                if type == 0x03 { name = String(decoding: data, as: UTF8.self) }
                if type == 0x51, data.count == 3, tempo == nil {
                    let micros = Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2])
                    if micros > 0 { tempo = (tick, micros) }
                }
                if type == 0x2F { break loop }
            case 0xF0, 0xF7:
                status = 0
                guard let length = reader.variableLength(), reader.take(length) != nil else { break loop }
            default:
                let channel = Int(first & 0x0F)
                switch first & 0xF0 {
                case 0x80, 0x90:
                    guard let pitch = reader.u8(), let velocity = reader.u8() else { break loop }
                    let key = channel * 128 + Int(pitch & 0x7F)
                    if first & 0xF0 == 0x90, velocity > 0 {
                        open[key, default: []].append((tick, Float(velocity) / 127))
                    } else {
                        close(key, at: tick)
                    }
                case 0xC0, 0xD0:
                    guard reader.u8() != nil else { break loop }
                default:                                               // aftertouch, controller, pitch bend
                    guard reader.u8() != nil, reader.u8() != nil else { break loop }
                }
            }
        }
        for key in open.keys.sorted() { while !(open[key] ?? []).isEmpty { close(key, at: tick) } }
        return (name, notes, tempo)
    }
}

/// Reads bytes in order and says nil instead of running off the end.
private struct ByteReader {
    let bytes: [UInt8]
    var position = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func peek() -> UInt8? { position < bytes.count ? bytes[position] : nil }
    mutating func skip(_ n: Int) { position = min(bytes.count, position + max(0, n)) }
    mutating func u8() -> UInt8? { guard let b = peek() else { return nil }; position += 1; return b }

    mutating func take(_ n: Int) -> [UInt8]? {
        guard n >= 0, position + n <= bytes.count else { return nil }
        defer { position += n }
        return Array(bytes[position..<(position + n)])
    }

    mutating func rest() -> [UInt8] { defer { position = bytes.count }; return Array(bytes[position...]) }

    mutating func u16() -> Int? { take(2).map { Int($0[0]) << 8 | Int($0[1]) } }
    mutating func u32() -> UInt32? { take(4).map { UInt32($0[0]) << 24 | UInt32($0[1]) << 16 | UInt32($0[2]) << 8 | UInt32($0[3]) } }

    /// MIDI's variable-length number: seven bits per byte, the top bit says another byte follows.
    mutating func variableLength() -> Int? {
        var value = 0
        for _ in 0..<4 {
            guard let b = u8() else { return nil }
            value = value << 7 | Int(b & 0x7F)
            if b & 0x80 == 0 { return value }
        }
        return nil
    }
}
