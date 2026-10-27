import AppKit
import SwiftUI

/// Tools for working with the library's data outside the app.
struct DeveloperSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Manual labels only", isOn: $model.exportManualLabelsOnly)
                Text("Off: every sample with a category is exported, with the one you set by hand where there is one and "
                     + "CLAP's own otherwise (the label's source is in the file). On: only samples you labelled yourself.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Export Embeddings…") { model.exportTrainingData() }
                        .disabled(!model.canExportTrainingData)
                    if model.trainingExportRunning { ProgressView().controlSize(.small) }
                    if let hint = model.trainingExportHint {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let result = model.trainingExportResult {
                    Text(result.message).font(.caption).foregroundStyle(result.failed ? .red : .secondary)
                        .textSelection(.enabled)
                    if let folder = result.folder {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                            .controlSize(.small)
                    }
                }
                Text("Writes a new folder with embeddings.npy (float32, one 512-number row per sample), labels.csv (path, category, "
                     + "source, CLAP's category and confidence, file fingerprint, one row per embedding in the same order) and "
                     + "metadata.json. Field recordings and samples without a category are left out. The library is not changed.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Training data") }
        }
        .formStyle(.grouped)
    }
}
