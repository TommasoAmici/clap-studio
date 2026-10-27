import ClapCore
import SwiftUI

struct EffectsView: View {
    @Bindable var workbench: EffectsWorkbench

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(workbench.samples.count) selected sample\(workbench.samples.count == 1 ? "" : "s")").font(.headline)
                Spacer()
                Menu("Add Effect") {
                    ForEach(workbench.bundles, id: \.self) { bundle in
                        Button(bundle.deletingPathExtension().lastPathComponent) { workbench.addBundle(bundle) }
                    }
                    if workbench.bundles.isEmpty { Text("No VST3 plugins installed") }
                }
                .disabled(workbench.busy || workbench.scanning)
                Button { workbench.rescan() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Rescan plugins").help("Rescan the standard VST3 folders").disabled(workbench.busy || workbench.scanning)
            }
            Text("The chain runs from top to bottom, after each sample’s trim and sound edits. Originals are only read.")
                .font(.caption).foregroundStyle(.secondary)
            if workbench.chain.isEmpty {
                ContentUnavailableView("Add a VST3 effect", systemImage: "slider.horizontal.3",
                                       description: Text("Install effects in ~/Library/Audio/Plug-Ins/VST3 or /Library/Audio/Plug-Ins/VST3, then rescan."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                    ForEach($workbench.chain) { $slot in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(slot.plugin.name).font(.headline)
                                Spacer()
                                Toggle("Bypass", isOn: $slot.bypass).toggleStyle(.checkbox)
                                Button { move(slot.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                    .accessibilityLabel("Move effect earlier").help("Move effect earlier").disabled(workbench.chain.first?.id == slot.id)
                                Button { move(slot.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                    .accessibilityLabel("Move effect later").help("Move effect later").disabled(workbench.chain.last?.id == slot.id)
                                Button { workbench.chain.removeAll { $0.id == slot.id } } label: { Image(systemName: "minus.circle") }
                                    .accessibilityLabel("Remove effect").help("Remove effect")
                            }
                            ForEach($slot.parameters) { $parameter in
                                HStack {
                                    Text(parameter.name).frame(width: 140, alignment: .leading).lineLimit(2)
                                    Slider(value: $parameter.value, in: 0...1, step: parameter.steps > 0 ? 1 / Double(parameter.steps) : 0.001)
                                        .accessibilityLabel(parameter.name)
                                    Text(parameter.value, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 45, alignment: .trailing)
                                }
                                .font(.caption)
                            }
                            if slot.parameters.isEmpty {
                                Text("This effect exposes no editable parameters.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    }
                }
                .disabled(workbench.busy)
            }
            HStack {
                Text("Extra tail")
                Slider(value: $workbench.tailSeconds, in: 0...10, step: 0.5).frame(maxWidth: 160)
                    .accessibilityLabel("Extra effect tail in seconds")
                Text("\(workbench.tailSeconds, specifier: "%.1f") s").monospacedDigit()
            }
            .font(.caption).disabled(workbench.busy)
            Text("Reported effect tails are included, up to 10 seconds per effect. Extra tail helps plugins that report none.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Picker("Sample", selection: $workbench.previewID) {
                    ForEach(workbench.samples) { sample in Text(sample.name).tag(Optional(sample.id)) }
                }
                .frame(maxWidth: 240).disabled(workbench.busy)
                Button("Preview") { workbench.preview() }.disabled(workbench.busy || workbench.chain.isEmpty)
                Button(workbench.busy ? "Cancel" : "Stop") { workbench.cancel() }
                Spacer()
                Button(workbench.samples.count > 1 ? "Bounce All…" : "Bounce…") { workbench.bounce() }
                    .disabled(workbench.busy || workbench.chain.isEmpty || workbench.samples.isEmpty)
            }
            Text(workbench.progress.isEmpty ? " " : workbench.progress)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(height: 16, alignment: .leading)
            if let message = workbench.message {
                ScrollView { Text(message).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 80)
            }
        }
        .padding(16)
        .onChange(of: workbench.chain) { workbench.cancel() }
        .onChange(of: workbench.previewID) { workbench.cancel() }
        .onChange(of: workbench.tailSeconds) { workbench.cancel() }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = workbench.chain.firstIndex(where: { $0.id == id }) else { return }
        let next = index + offset
        guard workbench.chain.indices.contains(next) else { return }
        workbench.chain.swapAt(index, next)
    }
}
