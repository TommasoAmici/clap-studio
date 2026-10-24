import ClapCore
import SwiftUI

/// A drawer for writing drum patterns at the project tempo.
struct DrumPanel: View {
    @Environment(AppModel.self) private var model
    @State private var naming = false
    @State private var grooveName = ""
    @State private var scroll = 0.0

    var body: some View {
        if model.showDrums {
            VStack(spacing: 0) {
                Divider()
                header
                barControls
                if model.drumPattern.tracks.isEmpty {
                    Text("Add sounds from the library or the kit builder to start a pattern.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .overlay(alignment: .top) { if model.dropHover == .drumInsert(0) { InsertionLine().offset(y: -1) } }
                } else {
                    let labels = model.drumPattern.displayLabels
                    VStack(spacing: 4) {
                        ForEach(Array(model.drumPattern.tracks.enumerated()), id: \.element.id) { index, track in
                            DrumTrackRow(index: index, track: track, title: labels.indices.contains(index) ? labels[index] : track.label, scroll: $scroll)
                                .overlay(alignment: .top) { if model.dropHover == .drumInsert(index) { InsertionLine().offset(y: -3) } }
                                .overlay(alignment: .bottom) {
                                    if index == model.drumPattern.tracks.count - 1, model.dropHover == .drumInsert(index + 1) {
                                        InsertionLine().offset(y: 3)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    DrumScrollControl(scroll: $scroll).padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            .background(.bar)
            .dropZone(.drums)
            .onAppear { scroll = Double(model.drumBar) * DrumGridLayout.barWidth }
            .onChange(of: model.drumPlaying) { _, playing in
                if playing { scroll = 0 }
            }
            .onChange(of: model.drumStep) { _, step in
                if let step { model.drumBar = step / DrumPattern.stepCount }
            }
            .onChange(of: model.drumPattern.bars) { _, bars in
                model.drumBar = min(model.drumBar, bars - 1)
            }
        }
    }

    private var barControls: some View {
        HStack(spacing: 8) {
            Text("Length").foregroundStyle(.secondary)
            TextField("Bars", value: Binding(get: { model.drumPattern.bars }, set: { model.drumPattern.setBars($0) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 65)
                .help("Number of 4/4 bars. Shortening removes steps past the end.")
            Text(model.drumPattern.bars == 1 ? "bar" : "bars").foregroundStyle(.secondary)
            Button("Open MIDI…") { model.chooseMidiFile(forDrums: true) }
                .help("Replace this beat with a MIDI file: one drum row per file track, snapped to sixteenth steps")
            Spacer()
        }
        .font(.caption).controlSize(.small)
        .padding(.horizontal, 16).padding(.bottom, 6)
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

    /// Tries other sounds on every track that is not locked, staying close to what is there.
    private var shuffleControls: some View {
        @Bindable var model = model
        return HStack(spacing: 2) {
            Button { model.shuffleDrumKit() } label: { Label("Shuffle Kit", systemImage: "dice") }
                .disabled(!model.canShuffleDrums)
                .help("Swap every unlocked track for a similar sound from the library. Lock the tracks you want to keep.")
            Menu {
                Picker("Variation", selection: $model.drumVariation) {
                    ForEach(DrumVariation.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline).labelsHidden()
            } label: { EmptyView() }
                .menuIndicator(.visible).fixedSize()
                .help("How far a swap may reach from the sound it replaces: \(model.drumVariation.rawValue)")
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
            shuffleControls
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

/// Shows where a dragged sound will be inserted: a line with a dot at its start, across the width of the track list.
private struct InsertionLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().frame(width: 8, height: 8)
            Rectangle().frame(height: 2)
        }
        .foregroundStyle(Color.accentColor)
        .frame(height: 8)
        .allowsHitTesting(false)
    }
}
