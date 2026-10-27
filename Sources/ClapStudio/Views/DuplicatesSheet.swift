import ClapCore
import SwiftUI

/// Lists groups of identical files. The best copy of each group is kept; the others are ticked to be hidden
/// (not deleted: hidden samples can be restored from the sidebar).
struct DuplicatesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var toHide: Set<Int64> = []
    @State private var seeded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 520)
        .onAppear { if model.duplicateGroups == nil { model.findDuplicates() } else { seed() } }
        .onChange(of: model.duplicateGroups) { seed() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicates").font(.title3.bold())
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Search Again") { seeded = false; model.findDuplicates() }
                .disabled(model.duplicateSearchRunning)
        }
        .padding(12)
    }

    private var summary: String {
        if model.duplicateSearchRunning { return "Comparing files…" }
        guard let groups = model.duplicateGroups else { return "" }
        let extras = groups.reduce(0) { $0 + $1.extras.count }
        return groups.isEmpty ? "No identical files found."
            : "\(groups.count) groups, \(extras) extra copies. The best copy of each is kept."
    }

    @ViewBuilder private var content: some View {
        if model.duplicateSearchRunning {
            VStack(spacing: 10) { ProgressView(); Text("Looking for copies…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let groups = model.duplicateGroups, !groups.isEmpty {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.ids, id: \.self) { id in
                            if let s = model.sampleByID[id] { row(s, keep: id == group.keeper) }
                        }
                    } header: {
                        Text("Identical files")
                    }
                }
            }
        } else {
            ContentUnavailableView("No duplicates", systemImage: "checkmark.circle")
        }
    }

    private func row(_ s: SampleRecord, keep: Bool) -> some View {
        HStack(spacing: 8) {
            if keep {
                Text("Keep").font(.caption.bold()).foregroundStyle(.green).frame(width: 52, alignment: .leading)
            } else {
                Toggle("Hide", isOn: Binding(get: { toHide.contains(s.id) },
                                             set: { if $0 { toHide.insert(s.id) } else { toHide.remove(s.id) } }))
                    .toggleStyle(.checkbox).frame(width: 52, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).lineLimit(1)
                Text(s.folder.isEmpty ? "/" : s.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(detail(s)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button { model.select(s.id, play: true) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless).help("Preview")
        }
    }

    private func detail(_ s: SampleRecord) -> String {
        let size = ByteCountFormatter.string(fromByteCount: s.size, countStyle: .file)
        let uses = s.useCount > 0 ? " · \(s.useCount)×" : ""
        return "\(Format.duration(s.duration)) · \(Int(s.sampleRate / 1000)) kHz · \(size)\(uses)"
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button("Hide \(toHide.count) Copies") {
                model.hide(Array(toHide))
                toHide = []
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(toHide.isEmpty)
        }
        .padding(12)
    }

    private func seed() {
        guard !seeded, let groups = model.duplicateGroups else { return }
        toHide = Set(groups.flatMap(\.extras))
        seeded = true
    }
}
