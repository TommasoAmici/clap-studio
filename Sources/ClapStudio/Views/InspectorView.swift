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
                    FileDragHandle(url: sample.url, title: sample.name) { model.registerGrab(sample.id) }
                        .frame(height: 44)
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
                Button { NSWorkspace.shared.activateFileViewerSelecting([s.url]) } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless).help("Reveal in Finder")
            }
        }
    }

    private func transport(_ s: SampleRecord) -> some View {
        HStack {
            Button {
                if model.playback.sampleID == s.id { model.player.stop() } else { model.playSample(s) }
            } label: {
                Image(systemName: model.playback.sampleID == s.id ? "stop.fill" : "play.fill").frame(width: 20)
            }
            .keyboardShortcut(.return, modifiers: [])
            Text("Space to play · M adds a cue · 1–9 jumps to a cue").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Find Similar") { model.viewMode = .library; model.showSimilar(to: s.id) }
                .help("Show this sample's neighbours")
        }
    }
}

struct SimilarList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Similar sounds").font(.subheadline.bold())
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
    @State private var confirmWrite = false
    @State private var keepBackup = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cue points").font(.subheadline.bold())
                Spacer()
                Button { model.addCueAtPlayhead() } label: { Image(systemName: "plus") }.help("Add cue at playhead (M)")
                Button { model.undoCue() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo cue edit").disabled(!(model.cueEditor?.canUndo ?? false))
                Button { model.redoCue() } label: { Image(systemName: "arrow.uturn.forward") }
                    .help("Redo cue edit").disabled(!(model.cueEditor?.canRedo ?? false))
            }
            .buttonStyle(.borderless)

            if model.cues.isEmpty {
                Text("Option-click the waveform or press M while playing to add one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(model.cues.enumerated()), id: \.element.id) { index, cue in
                CueRow(cue: cue, number: index + 1)
            }

            if model.canWriteCuesToFile || !model.cues.isEmpty {
                HStack {
                    if model.cuesDirty {
                        Label("Changes live in the app only", systemImage: "externaldrive.badge.xmark")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Re-read File") { model.reloadCuesFromFile() }.controlSize(.small)
                    Button("Write to File…") { confirmWrite = true }
                        .controlSize(.small).disabled(!model.canWriteCuesToFile)
                        .help(model.canWriteCuesToFile ? "Embed cues into the WAV file" : "Only WAV files can be written")
                }
            }
        }
        .confirmationDialog("Write cue points into \(model.selectedSample?.name ?? "this file")?",
                            isPresented: $confirmWrite, titleVisibility: .visible) {
            Button("Write and Keep Backup (.bak)") { model.writeCuesToFile(keepBackup: true) }
            Button("Write Without Backup", role: .destructive) { model.writeCuesToFile(keepBackup: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This modifies the audio file on disk. Only the cue chunks are rewritten; the audio data is verified to be unchanged.")
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
