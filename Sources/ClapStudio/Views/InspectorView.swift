import ClapCore
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let sample = model.selectedSample {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(sample)
                    WaveformCueView()
                    transport(sample)
                    FileDragHandle(url: sample.url) { model.registerGrab(sample.id) }
                        .frame(height: 44)
                    TrimPanel(sample: sample)
                    PropertiesPanel(sample: sample)
                    CuePanel()
                    SimilarList()
                }
                .padding(14)
            }
        } else {
            ContentUnavailableView("No sample selected", systemImage: "waveform",
                                   description: Text("Select a sample to preview it, set cue points and find similar sounds."))
        }
    }

    private func header(_ s: SampleRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.name).font(.headline).lineLimit(2)
            Text(s.relPath).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 10) {
                Text(Format.duration(s.duration))
                if s.sampleRate > 0 { Text(String(format: "%.1f kHz", s.sampleRate / 1000)) }
                if s.channels > 0 { Text(s.channels == 1 ? "mono" : s.channels == 2 ? "stereo" : "\(s.channels) ch") }
                Text(s.ext.uppercased())
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                UsageBadge(count: s.useCount)
                Text(s.useCount == 0 ? "never used" : "last used \(Format.date(s.lastUsed))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.toggleFavorite([s.id]) } label: { Image(systemName: s.favorite ? "star.fill" : "star") }
                    .buttonStyle(.borderless).foregroundStyle(s.favorite ? .yellow : .secondary)
                    .help(s.favorite ? "Remove from favorites (F)" : "Add to favorites (F)")
                Button { NSWorkspace.shared.activateFileViewerSelecting([s.url]) } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless).help("Reveal in Finder")
            }
        }
    }

    /// "Playing at 128 BPM, +2 st" when project matching bends this sample.
    private func fitNote(for s: SampleRecord) -> String? {
        let fit = model.adjustment(for: s)
        guard !fit.isNeutral else { return nil }
        var parts: [String] = []
        if fit.rate != 1, let bpm = model.project.bpm { parts.append(String(format: "%.0f BPM (×%.2f)", bpm, fit.rate)) }
        if fit.semitones != 0 { parts.append(String(format: "%+d st", fit.semitones)) }
        return "Fitted to project: " + parts.joined(separator: ", ")
    }

    private func transport(_ s: SampleRecord) -> some View {
        HStack {
            Button {
                if model.playback.sampleID == s.id { model.player.stop() } else { model.playSample(s) }
            } label: {
                Image(systemName: model.playback.sampleID == s.id ? "stop.fill" : "play.fill").frame(width: 20)
            }
            .keyboardShortcut(.return, modifiers: [])
            Text(fitNote(for: s) ?? "Space to play · M adds a cue · 1–9 jumps to a cue")
                .font(.caption2).foregroundStyle(fitNote(for: s) == nil ? Color.secondary : Color.accentColor)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            Button("Find Similar") { model.viewMode = .library; model.showSimilar(to: s.id) }
                .help("Show this sample's neighbours")
            Button("Build Kit") { model.buildKit(around: s.id) }
                .help("Suggest matching drums around this sample")
        }
    }
}

struct SimilarList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Similar sounds").font(.subheadline.bold())
                Spacer()
                if let sweep = model.sweepPosition {
                    Text("\(sweep.index) of \(sweep.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Text("← → to step through").font(.caption2).foregroundStyle(.tertiary)
            }
            AspectControls()
            if model.snapshot == nil {
                Text(model.isIndexing ? "Available once indexing finishes." : "Not analysed yet.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.similar.isEmpty {
                Text("No similar samples found.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.similar) { result in
                HStack(spacing: 8) {
                    ProgressView(value: Double(max(0, result.score)))
                        .progressViewStyle(.linear).frame(width: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(result.sample.name).lineLimit(1)
                        Text(result.sample.folder).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    UsageBadge(count: result.sample.useCount)
                }
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(model.selectedID == result.id ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { model.select(result.id, play: true) }
                .sampleDrag(result.sample, model: model)
            }
        }
    }
}

struct CuePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cue points").font(.subheadline.bold())
                Spacer()
                Button { model.addCueAtMarker() } label: { Image(systemName: "plus") }
                    .help("Add cue at the spot you clicked (M); at the playhead if you haven't clicked")
                Button { model.undoCue() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo cue edit").disabled(!(model.cueEditor?.canUndo ?? false))
                Button { model.redoCue() } label: { Image(systemName: "arrow.uturn.forward") }
                    .help("Redo cue edit").disabled(!(model.cueEditor?.canRedo ?? false))
            }
            .buttonStyle(.borderless)

            if let marker = model.startMarkerSeconds {
                Label("Start marker at \(Format.clock(marker)). Press M to set a cue here.", systemImage: "mappin")
                    .font(.caption).foregroundStyle(.cyan)
            } else if model.cues.isEmpty {
                Text("Click the waveform to audition from a spot, then press M to set a cue exactly there.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(model.cues.enumerated()), id: \.element.id) { index, cue in
                CueRow(cue: cue, number: index + 1)
            }

            if let note = model.cueFileNote {
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CueRow: View {
    @Environment(AppModel.self) private var model
    let cue: CuePoint
    let number: Int
    @State private var label = ""

    var body: some View {
        HStack(spacing: 6) {
            Button { model.playCue(cue) } label: {
                Text("\(number)").font(.caption.bold()).frame(width: 18, height: 18)
                    .background(model.selectedCueID == cue.id ? Color.yellow : Color.orange, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            Text(Format.clock(model.seconds(for: cue))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            TextField("Label", text: $label)
                .textFieldStyle(.plain)
                .onSubmit { model.renameCue(cue.id, to: label) }
            Image(systemName: cue.fileSynced ? "doc.badge.checkmark" : "internaldrive")
                .foregroundStyle(cue.fileSynced ? Color.green : Color.orange).imageScale(.small)
                .help(cue.fileSynced ? "Stored in the file" : "App only")
            Button { model.removeCue(cue.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).imageScale(.small)
        }
        .onAppear { label = cue.label }
        .onChange(of: cue.label) { _, new in label = new }
    }
}

/// Sliders for what "similar" should mean. Collapsed until asked for.
struct AspectControls: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        @Bindable var model = model
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 4) {
                slider("Overall sound", $model.aspectWeights.overall)
                slider("Brightness", $model.aspectWeights.brightness)
                slider("Pitch (same note)", $model.aspectWeights.pitch)
                slider("Level and punch", $model.aspectWeights.level)
                slider("Length", $model.aspectWeights.length)
                if !model.aspectWeights.isDefault {
                    Button("Reset") { model.aspectWeights = AspectWeights() }.controlSize(.small)
                }
            }
            .padding(.top, 4)
        } label: {
            Text(model.aspectWeights.isDefault ? "What counts as similar" : "What counts as similar (custom)")
                .font(.caption).foregroundStyle(model.aspectWeights.isDefault ? Color.secondary : Color.accentColor)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 110, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }
}
