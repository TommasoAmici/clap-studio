import ClapCore
import SwiftUI

/// Toolbar control for the project's tempo and key. With matching on, loops and tonal sounds preview in time and in key.
struct ProjectButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "metronome")
                if let summary { Text(summary).monospacedDigit() }
            }
        }
        .help("Project tempo and key")
        .popover(isPresented: $open) { ProjectEditor().padding(14).frame(width: 290) }
    }

    /// The tempo and key the project is set to, if any.
    private var summary: String? {
        let p = model.project
        var parts: [String] = []
        if let bpm = p.bpm { parts.append(String(format: bpm.rounded() == bpm ? "%.0f" : "%.1f", bpm)) }
        if let tonic = p.tonic { parts.append(tonic) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct ProjectEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Text("Project").font(.headline)
            HStack {
                Text("Tempo")
                TextField("BPM", value: $model.project.bpm, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).frame(width: 70).monospacedDigit()
                Text("BPM").foregroundStyle(.secondary)
                Spacer()
                Button("From selected") { model.useSelectedTempoForProject() }
                    .disabled(model.selectedSample?.effectiveBPM == nil).controlSize(.small)
            }
            HStack {
                Text("Key")
                Picker("Key", selection: $model.project.tonic) {
                    Text("None").tag(String?.none)
                    ForEach(DescriptorFilter.tonics, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden().frame(width: 90)
            }
            Divider()
            Toggle("Match tempo of loops", isOn: $model.project.matchTempo)
                .disabled(model.project.bpm == nil)
            Toggle("Match key of tonal sounds", isOn: $model.project.matchKey)
                .disabled(model.project.tonic == nil)
            Text("Previews are stretched or transposed to fit. Files are not changed, and dragging into your DAW gives the original.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
