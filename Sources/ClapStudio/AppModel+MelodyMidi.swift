import AppKit
import ClapCore
import Foundation
import UniformTypeIdentifiers

/// Bringing a MIDI file into the melody. The file is only read; its notes become melody tracks.
extension AppModel {
    func chooseMidiFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["mid", "midi"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Open"
        panel.message = "Choose a MIDI file. Its notes become melody tracks. The file is only read, never changed."
        if panel.runModal() == .OK, let url = panel.url { importMidi(url) }
    }

    /// Reads the file off the main thread, then replaces the melody with its notes.
    func importMidi(_ url: URL) {
        Task {
            let result = await Task.detached { Result { try MidiFile.read(url: url) } }.value
            switch result {
            case .failure(let error):
                let why = (error as? LocalizedError)?.errorDescription ?? "It could not be read."
                errorMessage = "Could not open \(url.lastPathComponent). \(why) The file was not changed."
            case .success(let tracks):
                applyMidi(tracks, named: url.lastPathComponent)
            }
        }
    }

    private func applyMidi(_ tracks: [MidiTrack], named name: String) {
        guard !tracks.isEmpty else { errorMessage = "\(name) has no notes."; return }
        guard !melodyHasNotes || confirmReplacingMelody(with: name) else { return }

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
