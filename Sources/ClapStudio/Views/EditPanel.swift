import ClapCore
import SwiftUI

/// Non-destructive sound edits: reverse, speed, filters and volume. What is chosen plays in previews and the drum
/// machine and is written by exports; the original file is never changed.
struct EditPanel: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var open = false
    @State private var draft = SampleEdit()

    var body: some View {
        let edit = model.selectedEdit
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Reverse", isOn: Binding(get: { draft.reverse }, set: { draft.reverse = $0; commit() }))
                    .toggleStyle(.checkbox)
                slider("Speed", value: $draft.speedSemitones, range: SampleEdit.speedRange, format: { String(format: "%+.1f st", $0) },
                       help: "Pitch and length together, like a tape: +12 is an octave up and half as long")
                slider("Volume", value: $draft.gainDB, range: SampleEdit.gainRange, format: { String(format: "%+.1f dB", $0) },
                       help: "Louder sounds are clipped at full scale")
                filter("Low-pass", isLowPass: true, hz: $draft.lowPassHz, help: "Removes what is above this frequency")
                filter("High-pass", isLowPass: false, hz: $draft.highPassHz, help: "Removes what is below this frequency")
                HStack {
                    Button { model.playSample(sample) } label: { Label("Edited", systemImage: "play.fill") }
                    Button("Original") { model.playSample(sample, fullFile: true) }
                    Spacer()
                    if !edit.isNeutral {
                        Button("Copy To…") { model.exportTrimmed(sample.id) }.help("Write the edited sound to a new WAV file")
                        Button("Reset") { model.resetEdit() }
                    }
                }
                .controlSize(.small)
                Text("The file is not changed. Drum machine, previews and copies use the edited sound; its similarity is still judged on the original.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            Text(edit.isNeutral ? "Edit sound" : "Edit sound: " + edit.summary).font(.subheadline.bold())
                .foregroundStyle(edit.isNeutral ? Color.primary : Color.accentColor).lineLimit(1)
        }
        .onAppear { draft = model.selectedEdit; open = !model.selectedEdit.isNeutral }
        .onChange(of: sample.id) { draft = model.selectedEdit; open = !model.selectedEdit.isNeutral }
        .onChange(of: model.selectedEdit) { _, new in draft = new }
    }

    private func commit() { model.setEdit(draft) }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String,
                        help: String) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { editing in if !editing { commit() } })
            Text(abs(value.wrappedValue) < 0.05 ? "off" : format(value.wrappedValue)).font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
        }
        .help(help)
    }

    /// A frequency on a logarithmic scale, with the far end meaning off.
    private func filter(_ title: String, isLowPass: Bool, hz: Binding<Double?>, help: String) -> some View {
        let range = SampleEdit.filterRange
        let position = Binding<Double>(
            get: { hz.wrappedValue.map { log(max($0, range.lowerBound) / range.lowerBound) / log(range.upperBound / range.lowerBound) } ?? (isLowPass ? 1 : 0) },
            set: { p in
                let off = isLowPass ? p >= 0.99 : p <= 0.01
                hz.wrappedValue = off ? nil : range.lowerBound * pow(range.upperBound / range.lowerBound, p)
            })
        return HStack {
            Text(title).font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: position, in: 0...1, onEditingChanged: { editing in if !editing { commit() } })
            Text(hz.wrappedValue.map(SampleEdit.hertz) ?? "off").font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
        }
        .help(help)
    }
}
