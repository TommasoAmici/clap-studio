import ClapCore
import SwiftUI

/// Filters on measured properties. Shown above both the list and the map, which share the result.
struct FilterBar: View {
    @Environment(AppModel.self) private var model
    @State private var showTempo = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Picker("Type", selection: $model.descriptorFilter.kind) {
                ForEach(DescriptorFilter.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 300)

            Button { showTempo.toggle() } label: {
                FilterLabel(tempoTitle, systemImage: "metronome")
            }
            .popover(isPresented: $showTempo) { TempoRangeEditor().padding(14) }

            Menu {
                Button("Any key") { model.descriptorFilter.tonic = nil }
                Divider()
                ForEach(DescriptorFilter.tonics, id: \.self) { tonic in
                    Button(tonic) { model.descriptorFilter.tonic = tonic }
                }
            } label: {
                FilterLabel(model.descriptorFilter.tonic.map { "Key: \($0)" } ?? "Key", systemImage: "music.note")
            }
            .menuStyle(.button).fixedSize()

            CategoryFilterMenu()
            MoodFilterMenu()

            if let example = model.exampleQuery {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                    Text("Like \(example.name)").lineLimit(1)
                    Button { model.clearExample() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            RecordButton()
            Spacer()
            if model.viewMode == .library {
                HStack(spacing: 2) {
                    Button { model.shuffleList() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .disabled(!model.canShuffle)
                        .tint(model.shuffleSeed == nil ? nil : .accentColor)
                        .help("Put the list in a random order (⌘R). Press again for another one.")
                    if model.shuffleSeed != nil {
                        Button { model.endShuffle() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).help("Back to sorted order")
                    }
                }
            }
            if model.descriptorFilter.isActive {
                Button("Clear") { model.descriptorFilter.reset() }.buttonStyle(.borderless)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }

    private var tempoTitle: String {
        let f = model.descriptorFilter
        switch (f.bpmMin, f.bpmMax) {
        case (nil, nil): return "Tempo"
        case let (lo?, hi?): return "\(Int(lo))–\(Int(hi)) BPM"
        case let (lo?, nil): return "≥ \(Int(lo)) BPM"
        case let (nil, hi?): return "≤ \(Int(hi)) BPM"
        }
    }
}

private struct TempoRangeEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Text("Tempo range").font(.headline)
            HStack {
                TextField("min", value: $model.descriptorFilter.bpmMin, format: .number).frame(width: 64)
                Text("to")
                TextField("max", value: $model.descriptorFilter.bpmMax, format: .number).frame(width: 64)
                Text("BPM").foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                ForEach([(70, 90), (90, 110), (110, 130), (130, 150), (150, 180)], id: \.0) { range in
                    Button("\(range.0)–\(range.1)") {
                        model.descriptorFilter.bpmMin = Double(range.0)
                        model.descriptorFilter.bpmMax = Double(range.1)
                    }
                }
            }
            .controlSize(.small)
            Text("Only samples with a detected or set tempo match.").font(.caption).foregroundStyle(.secondary)
            Button("Any tempo") { model.descriptorFilter.bpmMin = nil; model.descriptorFilter.bpmMax = nil }
        }
    }
}

struct CategoryFilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.categoryCounts.isEmpty {
            Menu {
                Button("Any category") { model.descriptorFilter.category = nil }
                Divider()
                ForEach(model.categoryCounts, id: \.name) { item in
                    Button("\(item.name) (\(item.count))") { model.descriptorFilter.category = item.name }
                }
            } label: {
                FilterLabel(model.descriptorFilter.category ?? "Category", systemImage: "tag")
            }
            .menuStyle(.button).fixedSize()
        }
    }
}

/// Moods can be combined: a sample matches when it has any of the ticked moods.
struct MoodFilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.moodCounts.isEmpty {
            Menu {
                Button("Any mood") { model.descriptorFilter.moods = [] }
                Divider()
                ForEach(model.moodCounts, id: \.name) { item in
                    Toggle("\(item.name) (\(item.count))", isOn: Binding(
                        get: { model.descriptorFilter.moods.contains(item.name) },
                        set: { on in
                            if on { model.descriptorFilter.moods.insert(item.name) }
                            else { model.descriptorFilter.moods.remove(item.name) }
                        }))
                }
            } label: {
                FilterLabel(title, systemImage: "face.smiling")
            }
            .menuStyle(.button).fixedSize()
        }
    }

    private var title: String {
        let moods = SoundMoods.sorted(Array(model.descriptorFilter.moods))
        switch moods.count {
        case 0: return "Mood"
        case 1, 2: return moods.joined(separator: ", ")
        default: return "\(moods.count) moods"
        }
    }
}

/// An icon and a title for a filter button. The icon gets a fixed-width slot and is centred on the text's line, so
/// icons of different shapes line up and sit at the same distance from their titles.
struct FilterLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).imageScale(.small).frame(width: 13)
            Text(title)
        }
    }
}

/// Listens through the microphone and finds library sounds like what it heard: beatbox a kick, tap a desk, hum a bass line.
struct RecordButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isRecording {
            HStack(spacing: 6) {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(.red).frame(width: geometry.size.width * CGFloat(min(1, model.recordingLevel.squareRoot())))
                    }
                }
                .frame(width: 60, height: 6)
                Text(String(format: "%.1f s", model.recordingSeconds)).monospacedDigit().foregroundStyle(.secondary)
                Button("Find Similar") { model.finishRecording() }
                Button { model.cancelRecording() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).help("Throw the recording away")
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.red.opacity(0.15), in: Capsule())
        } else {
            Button { model.toggleRecording() } label: { Image(systemName: "mic") }
                .disabled(model.recordingStarting)
                .help("Make a sound into the microphone (up to 10 seconds) and find library sounds like it")
        }
    }
}
