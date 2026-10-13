import ClapCore
import SwiftUI

/// What the file says about itself (title, description, keywords, UCS name, ...), with the two things to do about it:
/// make its keywords tags, and write the app's category and tags into the file.
struct FileInfoSection: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var meta: FileMetadata?

    private var reloadKey: String { "\(sample.id)|\(model.fileInfoRevision)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let meta, !meta.isEmpty { details(meta) }
            if model.canWriteTags(sample) {
                Button("Write Tags into File…") { model.tagWriteTargets = [sample.id] }
                    .controlSize(.small)
                    .help("Put this sample's category, tags and moods into the WAV file, where other software can read them")
            }
        }
        .task(id: reloadKey) { meta = model.fileMetadata(for: sample.id) }
    }

    private func details(_ meta: FileMetadata) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In the file").font(.subheadline.bold())
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 3) {
                row("Title", meta.title)
                row("Description", meta.description)
                row("Category", [meta.category, meta.subcategory].filter { !$0.isEmpty }.joined(separator: " / "))
                row("UCS", meta.ucsID)
                row("Creator", meta.creator)
                row("Source", meta.source)
                row("Made with", meta.originator)
                row("Date", meta.date)
            }
            .font(.caption)
            if !meta.keywords.isEmpty {
                Text(meta.keywords.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Use Keywords as Tags") { model.importFileKeywords([sample.id]) }.controlSize(.small)
            }
        }
    }

    @ViewBuilder private func row(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            GridRow(alignment: .top) {
                Text(title).foregroundStyle(.secondary)
                Text(value).lineLimit(4).textSelection(.enabled)
            }
        }
    }
}
