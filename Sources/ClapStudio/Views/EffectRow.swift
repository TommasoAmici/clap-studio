import ClapCore
import SwiftUI

struct EffectRow: View {
    @Binding var slot: EffectSlot
    @Bindable var workbench: EffectsWorkbench

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(slot.plugin.name).font(.headline).lineLimit(1).help(slot.plugin.name)
                Spacer(minLength: 0)
                Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Move effect earlier").help("Move effect earlier")
                    .disabled(workbench.chain.first?.id == slot.id)
                Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Move effect later").help("Move effect later")
                    .disabled(workbench.chain.last?.id == slot.id)
                Button { remove() } label: { Image(systemName: "minus.circle") }
                    .accessibilityLabel("Remove effect").help("Remove effect")
            }
            HStack {
                Toggle("Bypass", isOn: $slot.bypass).toggleStyle(.checkbox)
                Spacer()
                if slot.hasEditor {
                    Button("Open Editor…") { workbench.edit(slot.id) }
                        .help("Hear parameter changes while auditioning sounds in the Library or Map")
                }
            }
            if !slot.hasEditor {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(slot.parameters) { parameter in
                                HStack(spacing: 6) {
                                    Text(parameter.name).frame(width: 100, alignment: .leading).lineLimit(2)
                                    parameterSlider(parameter)
                                        .accessibilityLabel(parameter.name)
                                        .accessibilityValue(Text(displayValue(for: parameter)))
                                    Text(displayValue(for: parameter))
                                        .monospacedDigit().frame(width: parameterWidth, alignment: .trailing)
                                }
                                .font(.caption).id(parameter.id)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                    #if DEBUG
                    .onAppear {
                        guard ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_EFFECTS_LAST"] == "1",
                              let last = slot.parameters.last?.id else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                    #endif
                }
                if slot.parameters.isEmpty {
                    Text("This effect exposes no editable parameters.").font(.caption).foregroundStyle(.secondary)
                } else if slot.parameters.count > 6 {
                    Text("Scroll for more controls").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Play a sound while its editor is open to hear your changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            if slot.hasEditor { Button("Open Editor…") { workbench.edit(slot.id) } }
            Button("Move Effect Earlier") { move(by: -1) }.disabled(workbench.chain.first?.id == slot.id)
            Button("Move Effect Later") { move(by: 1) }.disabled(workbench.chain.last?.id == slot.id)
            Button(slot.bypass ? "Enable Effect" : "Bypass Effect") { slot.bypass.toggle() }
            Button("Remove Effect") { remove() }
        }
    }

    @ViewBuilder
    private func parameterSlider(_ parameter: VST3Parameter) -> some View {
        if parameter.steps > 0 {
            Slider(value: parameterBinding(parameter), in: 0...1, step: 1 / Double(parameter.steps))
        } else {
            Slider(value: parameterBinding(parameter), in: 0...1)
        }
    }

    private var parameterWidth: CGFloat {
        slot.plugin.builtIn == .lowPass || slot.plugin.builtIn == .highPass ? 58 : 35
    }

    private func displayValue(for parameter: VST3Parameter) -> String {
        slot.plugin.builtIn?.displayValue(for: parameter)
            ?? parameter.value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func parameterBinding(_ fallback: VST3Parameter) -> Binding<Double> {
        Binding(get: { slot.parameters.first(where: { $0.id == fallback.id })?.value ?? fallback.value },
                set: { value in
                    guard let index = slot.parameters.firstIndex(where: { $0.id == fallback.id }) else { return }
                    slot.parameters[index].value = value
                })
    }

    private func move(by offset: Int) {
        let id = slot.id
        workbench.moveEffect(id, by: offset)
    }

    private func remove() {
        let id = slot.id
        workbench.removeEffect(id)
    }
}
