import Foundation

/// Turns the tracks of a MIDI file into a melody: one melody track per MIDI track, all carrying the same sound until
/// the user picks others. The whole sequence is kept, however long and however many notes; only what cannot be held
/// (a fifth track, or music past `MelodyPattern.maxBars`) is left out, and `notice` says so in plain words.
public enum MelodyImport {
    /// `bars` is the length the user had chosen; a longer file grows the pattern to hold the whole sequence, but a
    /// shorter one never shrinks it.
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
            if midi.notes.contains(where: { $0.start + $0.length > steps }) { cut = true }
            pattern.setNotes(track: index, midi.notes.map {
                MelodyNote(pitch: $0.pitch, start: $0.start, length: $0.length, velocity: $0.velocity)
            })
        }

        var notices: [String] = []
        if tracks.count > used.count { notices.append("Used \(used.count) of \(tracks.count) tracks: the melody holds \(MelodyPattern.maxTracks).") }
        if cut { notices.append("Music after \(MelodyPattern.maxBars) bars was left out: that is far longer than a song, so the file may be damaged.") }
        return (pattern, notices.isEmpty ? nil : notices.joined(separator: " "))
    }
}
