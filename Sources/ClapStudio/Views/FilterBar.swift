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
            .pickerStyle(.segmented).labelsHidden().frame(width: 230)

            Button { showTempo.toggle() } label: {
                Label(tempoTitle, systemImage: "metronome")
            }
            .popover(isPresented: $showTempo) { TempoRangeEditor().padding(14) }

            Menu {
                Button("Any key") { model.descriptorFilter.tonic = nil }
                Divider()
                ForEach(DescriptorFilter.tonics, id: \.self) { tonic in
                    Button(tonic) { model.descriptorFilter.tonic = tonic }
                }
            } label: {
                Label(model.descriptorFilter.tonic.map { "Key: \($0)" } ?? "Key", systemImage: "music.note")
            }
            .menuStyle(.button).fixedSize()

            CategoryFilterMenu()

            Spacer()
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

/// Placeholder until sound categories exist.
struct CategoryFilterMenu: View {
    var body: some View { EmptyView() }
}
