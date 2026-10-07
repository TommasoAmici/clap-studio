import ClapCore
import SwiftUI

/// Measured properties of the selected sample, with an editable tempo.
struct PropertiesPanel: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var bpmText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Properties").font(.subheadline.bold())
            if sample.loudnessDB == nil {
                Text(model.isIndexing ? "Measuring…" : "Not measured yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    row("Type", sample.typeText)
                    if sample.isLoop == true { tempoRow }
                    row(sample.isLoop == true ? "Key" : "Note", sample.keyName ?? "–")
                    row("Level", sample.levelText)
                    row("Peak", sample.peakDB.map { String(format: "%.1f dB", $0) } ?? "")
                    row("Crest", sample.crestDB.map { String(format: "%.1f dB", $0) } ?? "")
                    row("Brightness", sample.brightnessText)
                }
                .font(.caption)
            }
        }
        .onAppear(perform: syncText)
        .onChange(of: sample.id) { syncText() }
        .onChange(of: sample.bpmManual) { syncText() }
    }

    private var tempoRow: some View {
        GridRow {
            Text("Tempo").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("BPM", text: $bpmText)
                    .textFieldStyle(.roundedBorder).frame(width: 64).monospacedDigit()
                    .onSubmit(commit)
                if sample.bpmManual != nil {
                    Button("Use detected") { model.setBPM(sample.id, nil) }.controlSize(.mini)
                        .help("Detected: \(sample.bpm.map { String(format: "%.1f", $0) } ?? "none")")
                } else {
                    Text("detected").foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value.isEmpty ? "–" : value).monospacedDigit()
        }
    }

    private func syncText() {
        bpmText = sample.effectiveBPM.map { String(format: $0.rounded() == $0 ? "%.0f" : "%.1f", $0) } ?? ""
    }

    private func commit() {
        if let value = Double(bpmText.replacingOccurrences(of: ",", with: ".")), (20...400).contains(value) {
            model.setBPM(sample.id, value)
        } else {
            syncText()
        }
    }
}
