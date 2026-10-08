import ClapCore
import SwiftUI

/// Copies the chosen samples to a folder, naming each from a template.
/// Trimmed samples are written as trimmed WAV files; the originals are never changed.
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("export.template") private var template = ExportNaming.defaultTemplate
    @AppStorage("export.bitDepth") private var bitDepth = ExportFormat.BitDepth.keep.rawValue
    @AppStorage("export.mono") private var mono = false
    @AppStorage("export.sampleRate") private var sampleRate = 0.0     // 0 keeps each file's own

    var body: some View {
        let samples = model.exportSamples
        let trimmed = samples.filter { model.activeTrim(for: $0) != nil }.count
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy \(model.samplesPhrase(samples.count))").font(.title3.bold())
            Text("The originals are not changed. Existing files in the destination are never overwritten."
                 + (trimmed > 0 ? " \(trimmed == 1 ? "1 sample is" : "\(trimmed) samples are") trimmed, so only the trimmed part is written, as a WAV file." : ""))
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("File names").font(.subheadline.bold())
                TextField("Template", text: $template).textFieldStyle(.roundedBorder).font(.body.monospaced())
                HStack(spacing: 6) {
                    ForEach(ExportNaming.tokens, id: \.self) { token in
                        Button("{\(token)}") { template += "{\(token)}" }.controlSize(.small)
                    }
                    Spacer()
                    Button("Reset") { template = ExportNaming.defaultTemplate }.controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview").font(.subheadline.bold())
                ForEach(Array(samples.prefix(4).enumerated()), id: \.element.id) { index, sample in
                    Text(ExportNaming.fileName(template: template, for: sample, position: index + 1, of: samples.count))
                        .font(.caption.monospaced()).lineLimit(1)
                }
                if samples.count > 4 { Text("and \(samples.count - 4) more").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Format").font(.subheadline.bold())
                HStack(spacing: 14) {
                    Picker("Bit depth", selection: $bitDepth) {
                        Text("Keep").tag(ExportFormat.BitDepth.keep.rawValue)
                        Text("16-bit").tag(ExportFormat.BitDepth.int16.rawValue)
                        Text("24-bit").tag(ExportFormat.BitDepth.int24.rawValue)
                    }
                    Picker("Sample rate", selection: $sampleRate) {
                        Text("Keep").tag(0.0)
                        Text("44.1 kHz").tag(44_100.0)
                        Text("48 kHz").tag(48_000.0)
                    }
                    Toggle("Mono", isOn: $mono)
                }
                .controlSize(.small)
                if !format.isDefault {
                    Text("Every file is converted and written as WAV, for samplers that need a particular format.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Folder…") {
                    dismiss()
                    model.exportSelection(template: template, format: format)
                }
                .keyboardShortcut(.defaultAction).disabled(samples.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private var format: ExportFormat {
        ExportFormat(bitDepth: ExportFormat.BitDepth(rawValue: bitDepth) ?? .keep, mono: mono, sampleRate: sampleRate > 0 ? sampleRate : nil)
    }
}
