import AppKit
import ClapCore
import Foundation

/// The outcome of the last training export, for the Developer settings.
struct TrainingExportResult {
    var message: String
    var folder: URL?
    var failed: Bool
}

extension AppModel {
    /// The library is embedded with the current model, so embeddings and labels belong together.
    var canExportTrainingData: Bool {
        guard let store else { return false }
        return !isIndexing && !trainingExportRunning && store.meta("model_version") == ClapEmbedder.versionTag
    }

    var trainingExportHint: String? {
        if store == nil { return "The library is not open." }
        if isIndexing { return "Available once indexing finishes." }
        if store?.meta("model_version") != ClapEmbedder.versionTag { return "Available once the library is embedded with the current model." }
        return nil
    }

    /// Asks for a folder, then writes embeddings and categories into a new folder inside it.
    func exportTrainingData() {
        guard canExportTrainingData, let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Choose where to create the export folder (embeddings.npy, labels.csv, metadata.json)."
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let manualOnly = exportManualLabelsOnly
        trainingExportRunning = true
        trainingExportResult = nil
        Task {
            let outcome = await Task.detached { () -> Result<TrainingExport.Summary, Error> in
                Result { try TrainingExport.write(store: store, into: parent, manualOnly: manualOnly) }
            }.value
            trainingExportRunning = false
            switch outcome {
            case .success(let s):
                var message = "Exported \(s.rows) samples (\(s.manual) manual, \(s.automatic) automatic) to \(s.folder.lastPathComponent)."
                var skipped: [String] = []
                if s.skippedUncategorised > 0 { skipped.append("\(s.skippedUncategorised) without a category") }
                if s.skippedFieldRecordings > 0 { skipped.append("\(s.skippedFieldRecordings) field recordings") }
                if s.skippedAutomatic > 0 { skipped.append("\(s.skippedAutomatic) with only an automatic category") }
                if !skipped.isEmpty { message += " Left out: " + skipped.joined(separator: ", ") + "." }
                trainingExportResult = TrainingExportResult(message: message, folder: s.folder, failed: false)
            case .failure(let error):
                trainingExportResult = TrainingExportResult(message: "Export failed: \(error)", folder: nil, failed: true)
            }
        }
    }
}
