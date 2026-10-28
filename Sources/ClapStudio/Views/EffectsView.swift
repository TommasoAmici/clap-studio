import ClapCore
import SwiftUI

/// A nonmodal chain beside the library, so different sounds can be tried quickly.
struct EffectsView: View {
    @Environment(AppModel.self) private var model
    @Bindable var workbench: EffectsWorkbench

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Effects", systemImage: "slider.horizontal.3").font(.headline)
                Toggle("Enabled", isOn: $workbench.enabled).toggleStyle(.checkbox)
                    .help("Play Library and Map auditions through this chain")
                Spacer()
                Menu("Add Effect") {
                    ForEach(workbench.bundles, id: \.self) { bundle in
                        Button(bundle.deletingPathExtension().lastPathComponent) { workbench.addBundle(bundle) }
                    }
                    if workbench.bundles.isEmpty { Text("No VST3 plugins installed") }
                }
                .disabled(workbench.busy || workbench.scanning).fixedSize()
                Button { workbench.rescan() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Rescan plugins").help("Rescan the standard VST3 folders")
                    .disabled(workbench.busy || workbench.scanning)
                Button { model.showEffects = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close effects drawer").help("Close effects and return to dry auditions")
            }
            if workbench.chain.isEmpty {
                Text("Add a VST3 effect, then select sounds in the Library or Map to hear the chain.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(workbench.chain) { slot in
                            EffectRow(slot: binding(for: slot), workbench: workbench)
                                .frame(width: 300)
                        }
                    }
                    .padding(.vertical, 2).frame(height: 141, alignment: .top)
                }
                .frame(height: 145)
                .disabled(workbench.busy)
            }
            HStack(spacing: 10) {
                Text("Left to right · originals are only read").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Extra tail").font(.caption)
                Slider(value: $workbench.tailSeconds, in: 0...10).frame(width: 90)
                    .accessibilityLabel("Extra effect tail in seconds")
                    .help("Allow more time for effects that report no ringing tail; silent padding is removed from bounces")
                    .disabled(workbench.busy)
                Text("\(workbench.tailSeconds, specifier: "%.1f") s").font(.caption).monospacedDigit().frame(width: 32)
                Button("Preview") { workbench.preview() }
                    .disabled(workbench.busy || workbench.chain.isEmpty || workbench.samples.isEmpty)
                Button(workbench.busy ? "Cancel" : "Stop") { model.stopAudition(); workbench.cancel() }
                Button(workbench.samples.count > 1 ? "Bounce All…" : "Bounce…") {
                    model.refreshEffectsSelection(forBounce: true); workbench.bounce()
                }
                .disabled(workbench.busy || workbench.chain.isEmpty || workbench.samples.isEmpty)
            }
            if !workbench.progress.isEmpty {
                Text(workbench.progress).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .controlSize(.small)
        .onChange(of: model.effectsActionTargets) { model.refreshEffectsSelection() }
        .onAppear { model.refreshEffectsSelection() }
    }

    /// A removed card can finish its last render without reading an invalid array index.
    private func binding(for fallback: EffectSlot) -> Binding<EffectSlot> {
        Binding(get: { workbench.chain.first(where: { $0.id == fallback.id }) ?? fallback },
                set: { updated in
                    guard let index = workbench.chain.firstIndex(where: { $0.id == fallback.id }) else { return }
                    workbench.chain[index] = updated
                })
    }
}
