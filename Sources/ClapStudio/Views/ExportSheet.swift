import ClapCore
import SwiftUI

/// Copies the tray's files to a folder, naming each from a template.
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("export.template") private var template = ExportNaming.defaultTemplate

    var body: some View {
        let samples = model.traySamples
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy \(samples.count) samples").font(.title3.bold())
            Text("The originals are not changed. Existing files in the destination are never overwritten.")
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

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Folder…") {
                    dismiss()
                    model.exportTray(template: template)
                }
                .keyboardShortcut(.defaultAction).disabled(samples.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480)
    }
}
