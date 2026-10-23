import Foundation

/// One row per MIDI track, with note starts snapped to sixteenth steps.
public enum DrumImport {
    /// Reads the file's own tracks, including a format-zero track with several MIDI channels.
    public static func read(url: URL) throws -> MidiSong {
        try MidiFile.readSong(url: url, splitChannels: false)
    }

    public static func pattern(from tracks: [MidiTrack], existing: DrumPattern = DrumPattern(),
                               selectedSampleID: Int64?) -> (pattern: DrumPattern, notice: String?) {
        let used = Array(tracks.prefix(DrumPattern.maxTracks))
        guard !used.isEmpty else { return (DrumPattern(), "That MIDI file has no notes.") }
        let limit = DrumPattern.maxBars * DrumPattern.stepCount
        var omitted = false
        let positions = used.map { track in
            track.notes.compactMap { note -> Int? in
                guard note.start.isFinite, note.start >= 0, note.start.rounded() < Double(limit) else {
                    omitted = true
                    return nil
                }
                return Int(note.start.rounded())
            }
        }
        let lastHit = positions.compactMap { $0.max() }.max() ?? 0
        let lastEnd = used.flatMap(\.notes).compactMap { note -> Double? in
            let end = note.start + note.length
            guard note.start.isFinite, note.start >= 0, end.isFinite, end >= 0, end <= Double(limit) else { return nil }
            return end
        }.max() ?? 0
        let bars = max((lastHit / DrumPattern.stepCount) + 1, Int(ceil(lastEnd / Double(DrumPattern.stepCount))))
        var pattern = DrumPattern(swing: existing.swing, bars: bars)
        for (index, midi) in used.enumerated() {
            let oldSound = existing.tracks.indices.contains(index) ? existing.tracks[index].sampleID : DrumTrack.unassignedSampleID
            let sampleID = oldSound == DrumTrack.unassignedSampleID ? selectedSampleID ?? DrumTrack.unassignedSampleID : oldSound
            let name = midi.name.trimmingCharacters(in: .whitespacesAndNewlines)
            pattern.addTrack(sampleID: sampleID, label: name.isEmpty ? "Track \(index + 1)" : name, category: nil, starter: false)
            for step in positions[index] { pattern.tracks[index].hits[step] = true }
        }
        var notices: [String] = []
        if tracks.count > used.count {
            notices.append("Used \(used.count) of \(tracks.count) tracks: the drum machine holds \(DrumPattern.maxTracks).")
        }
        if omitted { notices.append("Some note positions were damaged or beyond \(DrumPattern.maxBars) bars and were left out.") }
        return (pattern, notices.isEmpty ? nil : notices.joined(separator: " "))
    }
}
