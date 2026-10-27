import ClapCore
import SwiftUI

struct EffectRow: View {
    @Binding var slot: EffectSlot
    @Bindable var workbench: EffectsWorkbench

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slot.plugin.name).font(.headline)
                Spacer()
                Toggle("Bypass", isOn: $slot.bypass).toggleStyle(.checkbox)
                Button { move(by: -1) } label: { Image(systemName: "arrow.up") }
                    .accessibilityLabel("Move effect earlier").help("Move effect earlier")
                    .disabled(workbench.chain.first?.id == slot.id)
                Button { move(by: 1) } label: { Image(systemName: "arrow.down") }
                    .accessibilityLabel("Move effect later").help("Move effect later")
                    .disabled(workbench.chain.last?.id == slot.id)
                Button { remove() } label: { Image(systemName: "minus.circle") }
                    .accessibilityLabel("Remove effect").help("Remove effect")
            }
            if slot.hasEditor {
                Button("Open Editor…") { workbench.edit(slot.id) }
                    .help("Open the plug-in’s own controls. Close its window to use your edits.")
            } else {
                ForEach($slot.parameters) { $parameter in
                    HStack {
                        Text(parameter.name).frame(width: 140, alignment: .leading).lineLimit(2)
                        Slider(value: $parameter.value, in: 0...1, step: parameter.steps > 0 ? 1 / Double(parameter.steps) : 0.001)
                            .accessibilityLabel(parameter.name)
                        Text(parameter.value, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 45, alignment: .trailing)
                    }
                    .font(.caption)
                }
                if slot.parameters.isEmpty {
                    Text("This effect exposes no editable parameters.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            if slot.hasEditor { Button("Open Editor…") { workbench.edit(slot.id) } }
            Button("Move Effect Earlier") { move(by: -1) }.disabled(workbench.chain.first?.id == slot.id)
            Button("Move Effect Later") { move(by: 1) }.disabled(workbench.chain.last?.id == slot.id)
            Button(slot.bypass ? "Enable Effect" : "Bypass Effect") { slot.bypass.toggle() }
            Button("Remove Effect") { remove() }
        }
    }

    private func move(by offset: Int) {
        guard let index = workbench.chain.firstIndex(where: { $0.id == slot.id }) else { return }
        let next = index + offset
        guard workbench.chain.indices.contains(next) else { return }
        workbench.chain.swapAt(index, next)
    }

    private func remove() { workbench.chain.removeAll { $0.id == slot.id } }
}
