import Foundation

/// One note on the piano roll. Positions and lengths are in steps (a sixteenth note), so 4 steps are a beat and
/// 16 are a bar; they may be fractions, as notes read from a MIDI file are not always on the grid.
public struct MelodyNote: Identifiable, Equatable, Sendable, Codable {
    public static let pitchRange = 0...127
    /// The shortest note, a quarter of a step: shorter ones would only click.
    public static let minLength = 0.25

    public let id: UUID
    /// MIDI note number: 60 is middle C (shown as C4).
    public var pitch: Int
    public var start: Double
    public var length: Double
    /// How hard the note is played, 0 to 1.
    public var velocity: Float

    public init(id: UUID = UUID(), pitch: Int, start: Double, length: Double = 1, velocity: Float = 0.8) {
        self.id = id; self.pitch = pitch; self.start = start; self.length = length; self.velocity = velocity
    }

    public var end: Double { start + length }
}

/// One sound played as a melody: the sample, the note it sounds at when left alone, and the notes to play.
public struct MelodyTrack: Identifiable, Equatable, Sendable, Codable {
    /// Middle C, used when a sample has no pitch we can tell.
    public static let defaultRoot = 60
    public static let defaultVolume: Float = 0.9

    public let id: UUID
    /// nil while the track waits for a sound (a MIDI file brings notes but no sample).
    public var sampleID: Int64?
    public var label: String
    /// The note the sample sounds at when played unchanged; the other notes are tuned from it.
    public var rootNote: Int
    public var notes: [MelodyNote]
    public var volume: Float
    public var muted: Bool
    public var solo: Bool

    public init(id: UUID = UUID(), sampleID: Int64?, label: String, rootNote: Int = MelodyTrack.defaultRoot,
                notes: [MelodyNote] = [], volume: Float = MelodyTrack.defaultVolume, muted: Bool = false, solo: Bool = false) {
        self.id = id; self.sampleID = sampleID; self.label = label; self.rootNote = rootNote
        self.notes = notes; self.volume = volume; self.muted = muted; self.solo = solo
    }
}

/// Melodies on a piano roll, one or more bars long, played in time with the drum machine.
public struct MelodyPattern: Equatable, Sendable, Codable {
    public static let maxTracks = 4
    /// Long enough for a whole song section; longer MIDI files are cut here.
    public static let maxBars = 64
    public static let stepsPerBar = DrumPattern.stepCount

    public var tracks: [MelodyTrack] = []
    public private(set) var bars = 1

    public init(tracks: [MelodyTrack] = [], bars: Int = 1) {
        self.tracks = tracks
        self.bars = min(max(bars, 1), Self.maxBars)
    }

    public var stepCount: Int { bars * Self.stepsPerBar }

    // MARK: tracks

    /// Adds a track, or returns false when the melody is full.
    @discardableResult
    public mutating func addTrack(sampleID: Int64?, label: String, rootNote: Int = MelodyTrack.defaultRoot) -> Bool {
        guard tracks.count < Self.maxTracks else { return false }
        tracks.append(MelodyTrack(sampleID: sampleID, label: label, rootNote: rootNote))
        return true
    }

    public mutating func removeTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        tracks.remove(at: index)
    }

    // MARK: notes

    /// Adds a note, kept inside the keyboard and the pattern. A note of the same pitch that it overlaps is replaced.
    /// Returns nil when the track does not exist or the note would start after the end.
    @discardableResult
    public mutating func addNote(track: Int, pitch: Int, start: Double, length: Double = 1, velocity: Float = 0.8) -> UUID? {
        guard tracks.indices.contains(track) else { return nil }
        let steps = Double(stepCount)
        let begin = max(0, start)
        guard begin < steps else { return nil }
        let note = MelodyNote(pitch: Self.clamped(pitch), start: begin, length: min(max(length, MelodyNote.minLength), steps - begin),
                              velocity: min(max(velocity, 0), 1))
        tracks[track].notes.append(note)
        settle(track: track, keeping: note.id)
        return note.id
    }

    public mutating func removeNote(track: Int, id: UUID) {
        guard tracks.indices.contains(track) else { return }
        tracks[track].notes.removeAll { $0.id == id }
    }

    /// Moves a note to another pitch and time. It keeps its length unless that would run past the end.
    public mutating func moveNote(track: Int, id: UUID, pitch: Int, start: Double) {
        guard let (t, n) = locate(track: track, id: id) else { return }
        let steps = Double(stepCount)
        let begin = min(max(0, start), steps - MelodyNote.minLength)
        tracks[t].notes[n].pitch = Self.clamped(pitch)
        tracks[t].notes[n].start = begin
        tracks[t].notes[n].length = min(tracks[t].notes[n].length, steps - begin)
        settle(track: t, keeping: id)
    }

    public mutating func resizeNote(track: Int, id: UUID, length: Double) {
        guard let (t, n) = locate(track: track, id: id) else { return }
        let room = Double(stepCount) - tracks[t].notes[n].start
        tracks[t].notes[n].length = min(max(length, MelodyNote.minLength), room)
        settle(track: t, keeping: id)
    }

    public mutating func clearNotes() {
        for t in tracks.indices { tracks[t].notes = [] }
    }

    // MARK: length

    /// Sets the pattern length. Notes starting after the new end are dropped and the rest are cut at it.
    public mutating func setBars(_ newBars: Int) {
        bars = min(max(newBars, 1), Self.maxBars)
        let steps = Double(stepCount)
        for t in tracks.indices {
            tracks[t].notes = tracks[t].notes.compactMap { note in
                guard note.start < steps else { return nil }
                var copy = note
                copy.length = min(note.length, steps - note.start)
                return copy
            }
        }
    }

    /// Makes the pattern long enough for notes that end at `steps`, up to the longest allowed. Never shortens it.
    public mutating func growBars(toFit steps: Double) {
        guard steps.isFinite else { return }
        let needed = Int((steps / Double(Self.stepsPerBar)).rounded(.up))
        if needed > bars { bars = min(needed, Self.maxBars) }
    }

    // MARK: safety

    /// What was saved, made safe to play: a sensible length, no more tracks than fit, and every value in range.
    public func sanitized() -> MelodyPattern {
        var copy = MelodyPattern(tracks: Array(tracks.prefix(Self.maxTracks)), bars: bars)
        let steps = Double(copy.stepCount)
        for t in copy.tracks.indices {
            var track = copy.tracks[t]
            track.volume = track.volume.isFinite ? min(max(track.volume, 0), 1) : MelodyTrack.defaultVolume
            track.rootNote = Self.clamped(track.rootNote)
            track.notes = track.notes.compactMap { note in
                guard note.start.isFinite, note.start < steps else { return nil }
                var n = note
                n.pitch = Self.clamped(note.pitch)
                n.start = max(0, note.start)
                n.length = note.length.isFinite ? min(max(note.length, MelodyNote.minLength), steps - n.start) : steps - n.start
                n.velocity = note.velocity.isFinite ? min(max(note.velocity, 0), 1) : 0.8
                return n
            }
            copy.tracks[t] = track
        }
        return copy
    }

    // MARK: helpers

    private static func clamped(_ pitch: Int) -> Int { min(max(pitch, MelodyNote.pitchRange.lowerBound), MelodyNote.pitchRange.upperBound) }

    private func locate(track: Int, id: UUID) -> (Int, Int)? {
        guard tracks.indices.contains(track), let n = tracks[track].notes.firstIndex(where: { $0.id == id }) else { return nil }
        return (track, n)
    }

    /// Removes notes of the same pitch that the note `id` overlaps, so a row never has two notes sounding at once.
    private mutating func settle(track: Int, keeping id: UUID) {
        guard let mine = tracks[track].notes.first(where: { $0.id == id }) else { return }
        tracks[track].notes.removeAll {
            $0.id != id && $0.pitch == mine.pitch && $0.start < mine.end && mine.start < $0.end
        }
    }
}
