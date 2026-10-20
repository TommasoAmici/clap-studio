import ClapCore
import Foundation

/// The melodic sequencer: piano-roll tracks that play in time with the drum machine, sharing its tempo, swing and
/// play button.
extension AppModel {
    var melodyHasNotes: Bool { melodyPattern.tracks.contains { !$0.notes.isEmpty } }

    /// The play button works when either the drums or the melody has something to play.
    var canPlayPatterns: Bool { !drumPattern.tracks.isEmpty || melodyHasNotes }

    var currentMelodyTrack: MelodyTrack? {
        melodyPattern.tracks.indices.contains(selectedMelodyTrack) ? melodyPattern.tracks[selectedMelodyTrack] : nil
    }

    /// Sends the melody, and the files it needs, to the engine.
    func pushMelodyPattern() {
        var sources: [Int64: DrumSource] = [:]
        for track in melodyPattern.tracks {
            if let id = track.sampleID, let sample = sampleByID[id] { sources[id] = DrumSource(url: sample.url, trim: activeTrim(for: sample)) }
        }
        drumMachine.update(melody: melodyPattern, sources: sources)
    }

    /// The note a sample sounds at: its detected pitch when it has one, else middle C.
    func melodyRoot(of sample: SampleRecord) -> Int {
        sample.pitchHz.flatMap { NoteNames.midiNote(forHz: $0) } ?? MelodyTrack.defaultRoot
    }

    /// Adds samples as new melody tracks (up to the track limit) and opens the drawer on the last one.
    func addToMelody(_ ids: [Int64]) {
        var pattern = melodyPattern
        var skipped = 0
        for id in ids {
            guard let sample = sampleByID[id] else { continue }
            if !pattern.addTrack(sampleID: id, label: sample.name, rootNote: melodyRoot(of: sample)) { skipped += 1 }
        }
        melodyPattern = pattern
        selectedMelodyTrack = max(0, pattern.tracks.count - 1)
        showMelody = true
        if skipped > 0 { errorMessage = "The melody holds \(MelodyPattern.maxTracks) sounds. \(skipped) were left out." }
    }

    /// Puts a sample on a track in place of its sound, tuned from the sample's own note.
    func setMelodySample(track index: Int, to id: Int64) {
        guard melodyPattern.tracks.indices.contains(index), let sample = sampleByID[id] else { return }
        melodyPattern.tracks[index].sampleID = id
        melodyPattern.tracks[index].rootNote = melodyRoot(of: sample)
        melodyPattern.tracks[index].label = sample.name
    }

    func removeMelodyTrack(at index: Int) {
        melodyPattern.removeTrack(at: index)
        selectedMelodyTrack = min(selectedMelodyTrack, max(0, melodyPattern.tracks.count - 1))
        selectedMelodyNote = nil
    }

    func melodySampleName(_ track: MelodyTrack) -> String {
        guard let id = track.sampleID else { return "No sound yet" }
        guard let sample = sampleByID[id] else { return "Missing sample" }
        guard let trim = activeTrim(for: sample) else { return sample.name }
        return sample.name + (trim.coversWholeFile(duration: sample.duration) ? " · edited" : " · trimmed")
    }

    /// Deletes the note picked on the piano roll.
    func deleteSelectedMelodyNote() {
        guard let id = selectedMelodyNote else { return }
        melodyPattern.removeNote(track: selectedMelodyTrack, id: id)
        selectedMelodyNote = nil
    }
}
