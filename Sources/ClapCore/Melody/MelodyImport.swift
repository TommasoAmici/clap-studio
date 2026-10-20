import Foundation

/// Turns the tracks of a MIDI file into a melody: one melody track per MIDI track, all carrying the same sound until
/// the user picks others. Whatever does not fit is left out, and `notice` says so in plain words.
public enum MelodyImport {
    /// `bars` is the length the user had chosen; a longer file grows the pattern to hold the whole sequence (up to
    /// `MelodyPattern.maxBars`), but a shorter one never shrinks it.
    public static func pattern(from tracks: [MidiTrack], sampleID: Int64?, bars: Int,
                               rootNote: Int = MelodyTrack.defaultRoot) -> (pattern: MelodyPattern, notice: String?) {
        guard !tracks.isEmpty else { return (MelodyPattern(bars: bars), "That MIDI file has no notes.") }
        let used = Array(tracks.prefix(MelodyPattern.maxTracks))
        var pattern = MelodyPattern(bars: bars)
        pattern.growBars(toFit: used.map(\.endStep).max() ?? 0)
        let steps = Double(pattern.stepCount)

        var cut = false
        for (index, midi) in used.enumerated() {
            let name = midi.name.trimmingCharacters(in: .whitespacesAndNewlines)
            pattern.addTrack(sampleID: sampleID, label: name.isEmpty ? "Track \(index + 1)" : name, rootNote: rootNote)
            for note in midi.notes {
                if note.start + note.length > steps { cut = true }
                pattern.addNote(track: index, pitch: note.pitch, start: note.start, length: note.length, velocity: note.velocity)
            }
        }

        var notices: [String] = []
        if tracks.count > used.count { notices.append("Used \(used.count) of \(tracks.count) tracks: the melody holds \(MelodyPattern.maxTracks).") }
        if cut { notices.append("Notes after \(MelodyPattern.maxBars) bars were left out.") }
        return (pattern, notices.isEmpty ? nil : notices.joined(separator: " "))
    }
}
