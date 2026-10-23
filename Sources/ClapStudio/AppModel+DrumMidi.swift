import AppKit
import ClapCore
import Foundation

extension AppModel {
    func applyDrumMidi(_ song: MidiSong, named name: String, setTempo: Bool) {
        guard !song.tracks.isEmpty else { errorMessage = "\(name) has no notes."; return }
        if drumPattern.tracks.contains(where: { $0.hits.contains(true) }) {
            let alert = NSAlert()
            alert.messageText = "Replace the drum pattern with \(name)?"
            alert.informativeText = "The steps you have written are replaced by the notes in the file. This cannot be undone. The MIDI file is not changed."
            alert.addButton(withTitle: "Replace Pattern")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let imported = DrumImport.pattern(from: song.tracks, existing: drumPattern, selectedSampleID: selectedID)
        drumMachine.stop()
        drumPattern = imported.pattern
        drumBar = 0
        drumStep = nil
        drumPresetID = nil
        showDrums = true
        if setTempo {
            if let bpm = song.bpm {
                project.bpm = bpm
                statusMessage = "Project tempo set to \(Format.bpm(bpm)) BPM from \(name)"
            } else {
                statusMessage = "\(name) names no tempo, so the project tempo is unchanged"
            }
        }
        if let notice = imported.notice { errorMessage = notice }
    }
}
