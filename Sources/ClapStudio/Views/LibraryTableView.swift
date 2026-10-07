import ClapCore
import SwiftUI

struct LibraryTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let selection = Binding<Int64?>(get: { model.selectedID }, set: { model.select($0, play: true) })

        // The name and folder cells are drag sources (for dropping into a DAW). A drag source swallows the
        // click that would normally select the row, so those cells select and preview explicitly.
        Table(model.visible, selection: selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { s in
                HStack(spacing: 6) {
                    Image(systemName: "waveform").foregroundStyle(.secondary)
                    Text(s.name).lineLimit(1)
                    if s.status == .pending { ProgressView().controlSize(.mini) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { model.select(s.id, play: true) }
                .sampleDrag(s, model: model)
            }
            .width(min: 180, ideal: 260)
            TableColumn("Folder", value: \.folder) { s in
                Text(s.folder).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .onTapGesture { model.select(s.id, play: true) }
                    .sampleDrag(s, model: model)
            }
            .width(min: 100, ideal: 180)
            TableColumn("Length", value: \.duration) { s in
                Text(Format.duration(s.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(60)
            TableColumn("Cues", value: \.cueCount) { s in
                Text(s.cueCount == 0 ? "" : "\(s.cueCount)").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(44)
            TableColumn("Uses", value: \.useCount) { s in
                UsageBadge(count: s.useCount)
            }
            .width(56)
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if let id = ids.first, let s = model.sampleByID[id] {
                Button("Find Similar Sounds") { model.showSimilar(to: id) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([s.url]) }
            }
        } primaryAction: { ids in
            if let id = ids.first { model.select(id, play: true) }
        }
        .overlay {
            if model.visible.isEmpty && !model.isIndexing {
                ContentUnavailableView(model.samples.isEmpty ? "No samples yet" : "No matches",
                                       systemImage: "magnifyingglass")
            }
        }
    }
}

struct UsageBadge: View {
    let count: Int
    var body: some View {
        if count == 0 {
            Text("–").foregroundStyle(.tertiary)
        } else {
            Text("\(count)×").monospacedDigit().padding(.horizontal, 6)
                .background(Color.orange.opacity(min(0.15 + Double(count) * 0.05, 0.6)), in: Capsule())
        }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        if seconds < 10 { return String(format: "%.2fs", seconds) }
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : String(format: "%.1fs", seconds)
    }

    static func clock(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%d:%02d.%03d", ms / 60000, ms / 1000 % 60, ms % 1000)
    }

    static func date(_ ts: Double?) -> String {
        guard let ts else { return "never" }
        return Date(timeIntervalSince1970: ts).formatted(.relative(presentation: .named))
    }
}
