import ClapCore
import SwiftUI

/// A drawer with a piano roll for writing melodies that play in time with the drum machine, using the same tempo,
/// swing and play button.
struct MelodyPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.showMelody {
            VStack(spacing: 0) {
                Divider()
                header
                if let track = model.currentMelodyTrack {
                    trackControls(track, index: model.selectedMelodyTrack)
                    PianoRoll(trackIndex: model.selectedMelodyTrack).frame(height: 168)
                } else {
                    Text("Drag a sound here, or use Add to Melody in the library menu, to write a melody with it. A MIDI file can be dropped here too.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            .background(.bar)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: model.dropHover == .melody ? 2 : 0).padding(2))
            .dropZone(.melody)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { model.toggleDrumPlayback() } label: {
                Image(systemName: model.drumPlaying ? "stop.fill" : "play.fill").frame(width: 16)
            }
            .disabled(!model.canPlayPatterns)
            .help(model.drumPlaying ? "Stop" : "Play the melody and the drum machine in a loop")
            Text("Melody").font(.caption.bold()).lineLimit(1).fixedSize()
            trackTabs
            Button { model.addToMelody(model.actionTargets) } label: { Label("Add Selected", systemImage: "plus") }
                .disabled(model.actionTargets.isEmpty || model.melodyPattern.tracks.count >= MelodyPattern.maxTracks)
                .help("Give the melody another sound: the selected sample")
            Button("Open MIDI…") { model.chooseMidiFile() }
                .help("Replace the melody with the notes of a MIDI file, one track for each track in it. The file's tempo is not used: the melody follows the project tempo.")
            Spacer()
            barsMenu
            Button("Clear Notes") { model.melodyPattern.clearNotes(); model.selectedMelodyNote = nil }
                .disabled(!model.melodyHasNotes)
            Button { model.showMelody = false } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).help("Close the melody")
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// One tab per track, coloured like its notes.
    private var trackTabs: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.melodyPattern.tracks.enumerated()), id: \.element.id) { index, track in
                let colour = melodyTrackColors[index % melodyTrackColors.count]
                Button { model.selectedMelodyTrack = index; model.selectedMelodyNote = nil } label: {
                    HStack(spacing: 4) {
                        Circle().fill(colour).frame(width: 7, height: 7)
                        Text(track.label).lineLimit(1).frame(maxWidth: 110)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(index == model.selectedMelodyTrack ? colour.opacity(0.25) : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(model.melodySampleName(track))
            }
        }
    }

    /// 1, 2 and 4 bars, plus whatever length a longer MIDI file made it.
    private var barsMenu: some View {
        let current = model.melodyPattern.bars
        let choices = Array(Set([1, 2, 4, current])).sorted()
        return Picker("Length", selection: Binding(get: { current }, set: { model.melodyPattern.setBars($0); model.selectedMelodyNote = nil })) {
            ForEach(choices, id: \.self) { Text($0 == 1 ? "1 bar" : "\($0) bars").tag($0) }
        }
        .fixedSize()
        .help("How long the melody is before it starts again. The drums keep looping every bar. Shortening it removes the notes past the end.")
    }

    private func trackControls(_ track: MelodyTrack, index: Int) -> some View {
        HStack(spacing: 8) {
            Button { if let id = track.sampleID { model.select(id, play: true) } } label: {
                Text(model.melodySampleName(track)).font(.caption).lineLimit(1)
                    .foregroundStyle(track.sampleID != nil && model.sampleByID[track.sampleID!] == nil ? Color.orange : Color.primary)
            }
            .buttonStyle(.plain).disabled(track.sampleID == nil).help("Preview this sound")
            Button { if let id = model.selectedID { model.setMelodySample(track: index, to: id) } } label: {
                Image(systemName: "arrow.left.arrow.right.square")
            }
            .buttonStyle(.borderless).disabled(model.selectedID == nil || model.selectedID == track.sampleID)
            .help("Use the selected sample for this track")
            Spacer()
            Stepper(value: Binding(get: { track.rootNote }, set: { model.melodyPattern.tracks[index].rootNote = $0 }), in: 0...127) {
                Text("Plays at \(NoteNames.name(midi: track.rootNote))").font(.caption).monospacedDigit()
            }
            .help("The note this sample sounds at as recorded. The other notes are tuned from it, like a tape.")
            toggle("M", on: track.muted, color: .orange, help: "Mute") { model.melodyPattern.tracks[index].muted.toggle() }
            toggle("S", on: track.solo, color: .yellow, help: "Solo") { model.melodyPattern.tracks[index].solo.toggle() }
            Slider(value: Binding(get: { Double(track.volume) }, set: { model.melodyPattern.tracks[index].volume = Float($0) }), in: 0...1)
                .frame(width: 70).controlSize(.mini)
            Button { model.removeMelodyTrack(at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help("Remove this track")
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func toggle(_ title: String, on: Bool, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption2.bold()).frame(width: 18, height: 18)
                .background(on ? color : Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(on ? Color.black : Color.secondary)
        }
        .buttonStyle(.plain).help(help)
    }
}
