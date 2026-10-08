import ClapCore
import SwiftUI

/// A drawer with a 16-step sequencer for auditioning samples together at the project tempo.
struct DrumPanel: View {
    @Environment(AppModel.self) private var model
    @State private var naming = false
    @State private var grooveName = ""

    var body: some View {
        if model.showDrums {
            VStack(spacing: 0) {
                Divider()
                header
                if model.drumPattern.tracks.isEmpty {
                    Text("Add sounds from the library or the kit builder to start a pattern.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    let labels = model.drumPattern.displayLabels
                    VStack(spacing: 4) {
                        ForEach(Array(model.drumPattern.tracks.enumerated()), id: \.element.id) { index, track in
                            DrumTrackRow(index: index, track: track, title: labels.indices.contains(index) ? labels[index] : track.label)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
            .background(.bar)
            .dropZone(.drums)
        }
    }

    /// Ready-made grooves, the user's own, and saving the pattern on screen as a new one.
    private var grooveMenu: some View {
        Menu {
            Picker("Groove", selection: Binding(get: { model.drumPresetID }, set: { model.selectDrumPreset($0) })) {
                Text("Starter rhythms").tag(String?.none)
                ForEach(DrumPreset.all) { Text($0.name).tag(String?.some($0.id)) }
                if !model.userDrumPresets.isEmpty {
                    Divider()
                    ForEach(model.userDrumPresets) { Text($0.name).tag(String?.some($0.id)) }
                }
            }
            .pickerStyle(.inline).labelsHidden()
            Divider()
            Button("Save Pattern as Groove…") { grooveName = ""; naming = true }
                .disabled(!model.drumPattern.tracks.contains { $0.hits.contains(true) })
            if !model.userDrumPresets.isEmpty {
                Menu("Delete Groove") {
                    ForEach(model.userDrumPresets) { preset in
                        Button(preset.name, role: .destructive) { model.deleteDrumPreset(preset.id) }
                    }
                }
            }
        } label: {
            Text(model.drumPreset?.name ?? "Starter rhythms")
        }
        .fixedSize()
        .help("A groove sets the project tempo and swing and gives each sound a rhythm that fits its category. Save your own from the pattern on screen.")
        .alert("Save Groove", isPresented: $naming) {
            TextField("Name", text: $grooveName)
            Button("Save") { model.saveDrumPreset(named: grooveName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps these rhythms, the swing and the project tempo. Saving under an existing name replaces it.")
        }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Button { model.toggleDrumPlayback() } label: {
                Image(systemName: model.drumPlaying ? "stop.fill" : "play.fill").frame(width: 16)
            }
            .disabled(model.drumPattern.tracks.isEmpty)
            .help(model.drumPlaying ? "Stop the pattern" : "Play the pattern in a loop")
            Text("Drum machine").font(.caption.bold()).lineLimit(1).fixedSize()
            grooveMenu
            HStack(spacing: 4) {
                TextField("BPM", value: $model.project.bpm, format: .number.precision(.fractionLength(0...1)),
                          prompt: Text(String(format: "%.0f", DrumTiming.defaultBPM)))
                    .textFieldStyle(.roundedBorder).frame(width: 60).monospacedDigit()
                Text("BPM").foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            .help("The project tempo")
            HStack(spacing: 4) {
                Text("Swing").foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Slider(value: Binding(get: { DrumTiming.swingPercent(model.drumPattern.swing) },
                                      set: { model.drumPattern.swing = DrumTiming.swing(percent: $0.rounded()) }),
                       in: 25...75)
                    .frame(minWidth: 50, idealWidth: 100, maxWidth: 100)
                Text("\(Int(DrumTiming.swingPercent(model.drumPattern.swing).rounded()))%")
                    .monospacedDigit().lineLimit(1).fixedSize().frame(minWidth: 34, alignment: .trailing)
                    .onTapGesture(count: 2) { model.drumPattern.swing = 0 }
            }
            .help("50% is straight. Higher pushes every second step late, lower pulls it early. Double-click the value to reset.")
            Spacer()
            VolumeControl()      // while the drum machine is open the volume sits here; its buttons are in the status bar
            Button { model.showDrums = false; model.drumMachine.stop() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).help("Close the drum machine")
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// The drum machine's buttons. They live in the status bar while the drum machine is open.
struct DrumActions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Button("Add Selected") { model.addToDrums(model.actionTargets) }
                .disabled(model.actionTargets.isEmpty || model.drumPattern.isFull)
            if model.squidEnabled {
                Button("Send to Squid…") { model.openSquidExport(ids: model.drumPattern.tracks.map(\.sampleID)) }
                    .disabled(model.drumPattern.tracks.isEmpty)
                    .help("Send these sounds to a Squid Salmple USB stick")
            }
            Button("Clear Steps") { model.drumPattern.clearHits() }
                .disabled(model.drumPattern.tracks.isEmpty)
            Button("Remove All") { model.drumMachine.stop(); model.drumPattern = DrumPattern(swing: model.drumPattern.swing) }
                .disabled(model.drumPattern.tracks.isEmpty)
        }
        .controlSize(.small)
        .lineLimit(1).fixedSize()
    }
}

/// The overall preview volume.
struct VolumeControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.fill").imageScale(.small)
            Slider(value: Binding(get: { Double(model.volume) }, set: { model.volume = Float($0) }), in: 0...1)
                .frame(width: 90).controlSize(.small)
        }
    }
}

private struct DrumTrackRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let track: DrumTrack
    let title: String
    private var dropTargeted: Bool { model.dropHover == .drumTrack(index) }

    var body: some View {
        HStack(spacing: 8) {
            Button { model.select(track.sampleID, play: true) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.caption.bold()).lineLimit(1)
                    Text(model.drumSampleName(track)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Preview this sound")
            HStack(spacing: 2) {
                Button { model.cycleDrumSample(track: index, by: -1) } label: { Image(systemName: "chevron.left") }
                Button { model.cycleDrumSample(track: index, by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless).disabled(track.alternatives.count < 2).help("Try another sound from the kit")
            Button { if let id = model.selectedID { model.replaceDrumSample(track: index, with: id) } } label: {
                Image(systemName: "arrow.left.arrow.right.square")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedID == nil || model.selectedID == track.sampleID)
            .help("Replace this sound with the selected sample (or drag a sample onto the track)")
            steps
            toggle("M", on: track.muted, color: .orange, help: "Mute") { model.drumPattern.tracks[index].muted.toggle() }
            toggle("S", on: track.solo, color: .yellow, help: "Solo") { model.drumPattern.tracks[index].solo.toggle() }
            Slider(value: Binding(get: { Double(track.volume) },
                                  set: { model.drumPattern.tracks[index].volume = Float($0) }), in: 0...1)
                .frame(width: 70).controlSize(.mini)
            Button { model.drumPattern.removeTrack(at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help("Remove this track")
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(dropTargeted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 1.5 : 0))
        .dropZone(.drumTrack(index))
        .contextMenu {
            if let id = model.selectedID, id != track.sampleID {
                Button("Use Selected Sample Here") { model.replaceDrumSample(track: index, with: id) }
            }
        }
    }

    private var steps: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { group in
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { n in
                        let step = group * 4 + n
                        StepCell(on: track.hits[step], playing: model.drumStep == step, beat: n == 0)
                            .onTapGesture { model.drumPattern.toggle(track: index, step: step) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
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

private struct StepCell: View {
    let on: Bool
    let playing: Bool
    let beat: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(on ? Color.accentColor : Color.secondary.opacity(beat ? 0.32 : 0.18))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(playing ? Color.white.opacity(0.9) : .clear, lineWidth: 1.5))
            .frame(minWidth: 16, maxWidth: 34, minHeight: 22, maxHeight: 22)
            .contentShape(Rectangle())
    }
}
