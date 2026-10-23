import AppKit
import ClapCore
import Foundation
import UniformTypeIdentifiers

/// Bringing MIDI files into either sequencer. The file is only read.
extension AppModel {
    /// Whether the Open panel's "set the project tempo" box starts ticked: as the user last left it, ticked at first.
    private static let midiSetsTempoKey = "melody.midiSetsTempo"

    func chooseMidiFile(forDrums: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["mid", "midi"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Open"
        panel.message = forDrums
            ? "Choose a MIDI file. Each track becomes a drum row, with note starts snapped to sixteenth steps. The file is only read, never changed."
            : "Choose a MIDI file. Its notes become melody tracks. The file is only read, never changed."
        let setsTempo = NSButton(checkboxWithTitle: "Also set the project tempo to the tempo in the file", target: nil, action: nil)
        let tempoKey = forDrums ? "drum.midiSetsTempo" : Self.midiSetsTempoKey
        setsTempo.state = (UserDefaults.standard.object(forKey: tempoKey) as? Bool ?? true) ? .on : .off
        setsTempo.sizeToFit()
        panel.accessoryView = setsTempo
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(setsTempo.state == .on, forKey: tempoKey)
            importMidi(url, setTempo: setsTempo.state == .on, forDrums: forDrums)
        }
    }

    /// Reads the file off the main thread, then replaces the melody with its notes. A file dropped on the window
    /// leaves the project tempo alone; the Open panel can ask for it to be set from the file.
    func importMidi(_ url: URL, setTempo: Bool = false, forDrums: Bool = false) {
        midiImportTask?.cancel()
        midiImportTask = Task {
            let result = await Task.detached {
                Result { try forDrums ? DrumImport.read(url: url) : MidiFile.readSong(url: url) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .failure(let error):
                let why = (error as? LocalizedError)?.errorDescription ?? "It could not be read."
                errorMessage = "Could not open \(url.lastPathComponent). \(why) The file was not changed."
            case .success(let song):
                if forDrums { applyDrumMidi(song, named: url.lastPathComponent, setTempo: setTempo) }
                else { applyMidi(song, named: url.lastPathComponent, setTempo: setTempo) }
            }
        }
    }

    private func applyMidi(_ song: MidiSong, named name: String, setTempo: Bool) {
        let tracks = song.tracks
        guard !tracks.isEmpty else { errorMessage = "\(name) has no notes."; return }
        guard !melodyHasNotes || confirmReplacingMelody(with: name) else { return }
        if setTempo {
            if let bpm = song.bpm {
                project.bpm = bpm
                statusMessage = "Project tempo set to \(Format.bpm(bpm)) BPM from \(name)"
            } else {
                statusMessage = "\(name) names no tempo, so the project tempo is unchanged"
            }
        }

        // Each track keeps the sound of the track it replaces; extra ones start with the selected sample.
        let old = melodyPattern
        let chosen = selectedSample
        let imported = MelodyImport.pattern(from: tracks, sampleID: chosen?.id, bars: old.bars,
                                            rootNote: chosen.map { melodyRoot(of: $0) } ?? MelodyTrack.defaultRoot)
        var pattern = imported.pattern
        for index in pattern.tracks.indices where old.tracks.indices.contains(index) && old.tracks[index].sampleID != nil {
            pattern.tracks[index].sampleID = old.tracks[index].sampleID
            pattern.tracks[index].rootNote = old.tracks[index].rootNote
        }
        melodyPattern = pattern
        selectedMelodyTrack = 0
        selectedMelodyNote = nil
        showMelody = true
        if let notice = imported.notice { errorMessage = notice }
    }

    private func confirmReplacingMelody(with name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace the melody with \(name)?"
        alert.informativeText = "The notes you have written are replaced by the notes in the file. This cannot be undone. The MIDI file is not changed."
        alert.addButton(withTitle: "Replace Melody")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
