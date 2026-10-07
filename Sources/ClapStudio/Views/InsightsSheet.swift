import ClapCore
import SwiftUI

/// "You keep reaching for these. Have you tried these?" Fresh sounds that sit next to your most-used ones.
struct InsightsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let suggestions = model.reuseSuggestions()
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fresh alternatives").font(.title3.bold())
                    Text("Sounds close to the ones you grab most, that you have never used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            Divider()
            if suggestions.isEmpty {
                ContentUnavailableView("Nothing to suggest yet", systemImage: "lightbulb",
                                       description: Text("Drag a few samples into your DAW. They are counted, and this list fills with similar sounds you have not tried."))
            } else {
                List {
                    ForEach(suggestions) { suggestion in
                        if let favorite = model.sampleByID[suggestion.favoriteID] {
                            Section {
                                ForEach(suggestion.alternatives, id: \.id) { alt in
                                    if let s = model.sampleByID[alt.id] { row(s, score: alt.score) }
                                }
                            } header: {
                                HStack {
                                    Text(favorite.name).font(.subheadline.bold())
                                    UsageBadge(count: suggestion.uses)
                                    Spacer()
                                    Button { model.select(favorite.id, play: true) } label: { Image(systemName: "play.fill") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 520)
    }

    private func row(_ s: SampleRecord, score: Float) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(max(0, score))).progressViewStyle(.linear).frame(width: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.name).lineLimit(1)
                Text(s.folder.isEmpty ? "/" : s.folder).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.addToTray([s.id]) } label: { Image(systemName: "tray.and.arrow.down") }
                .buttonStyle(.borderless).help("Add to the tray")
            Button { model.select(s.id, play: true) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless).help("Preview")
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(s.id, play: true) }
        .sampleDrag(s, model: model)
    }
}
