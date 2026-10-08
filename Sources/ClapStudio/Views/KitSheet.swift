import ClapCore
import SwiftUI

/// Builds a drum kit around one sample: a suggestion per category, with alternatives a click away.
struct KitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kit builder").font(.title3.bold())
                Text("Sounds that go with your pick: similar character, matching level, same pack when there is one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            Divider()
            if model.kitSlots.isEmpty {
                ContentUnavailableView("No kit to suggest", systemImage: "square.grid.3x3",
                                       description: Text("Categories are needed to find matching sounds. They appear once indexing finishes."))
            } else {
                List(model.kitSlots) { slot in row(slot) }
            }
            Divider()
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add to Tray") { model.addToTray(model.kitSamples.map(\.id)); dismiss() }
                Button("Save as Collection…") { model.newCollectionSeed = model.kitSamples.map(\.id); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(model.kitSamples.isEmpty)
            .padding(12)
        }
        .frame(width: 560, height: 480)
    }

    private func row(_ slot: KitSlot) -> some View {
        HStack(spacing: 10) {
            Text(slot.category).font(.callout.bold()).frame(width: 90, alignment: .leading)
            if let pick = model.kitPick(slot) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.name).lineLimit(1)
                    Text(pick.folder.isEmpty ? "/" : pick.folder).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.select(pick.id, play: true) }
                .sampleDrag(pick, model: model)
            }
            Spacer()
            if slot.isAnchor {
                Text("Your pick").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\((model.kitChoice[slot.category] ?? 0) + 1) of \(slot.candidates.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button { model.cycleKit(slot, by: -1) } label: { Image(systemName: "chevron.left") }
                Button { model.cycleKit(slot, by: 1) } label: { Image(systemName: "chevron.right") }
            }
            if let pick = model.kitPick(slot) {
                Button { model.select(pick.id, play: true) } label: { Image(systemName: "play.fill") }.help("Preview")
            }
        }
        .buttonStyle(.borderless)
    }
}
