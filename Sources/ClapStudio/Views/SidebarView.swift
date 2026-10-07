import ClapCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    private var selection: Binding<String?> {
        Binding(
            get: {
                if let folder = model.folderSelection { return folder }
                if let category = model.descriptorFilter.category { return "cat.\(category)" }
                return "smart.\(model.smartFilter.rawValue)"
            },
            set: { new in
                guard let new else { return }
                if new.hasPrefix("cat.") {
                    model.folderSelection = nil
                    model.smartFilter = .all
                    model.descriptorFilter.category = String(new.dropFirst(4))
                } else if new.hasPrefix("smart.") {
                    model.folderSelection = nil
                    model.descriptorFilter.category = nil
                    model.smartFilter = SmartFilter(rawValue: String(new.dropFirst(6))) ?? .all
                } else {
                    model.descriptorFilter.category = nil
                    model.smartFilter = .all
                    model.folderSelection = new
                }
            })
    }

    var body: some View {
        List(selection: selection) {
            Section("Filters") {
                ForEach(SmartFilter.allCases.filter { $0 != .hidden || model.hiddenCount > 0 }) { filter in
                    Label(filter.rawValue, systemImage: filter.symbol).tag("smart.\(filter.rawValue)")
                }
            }
            if !model.categoryCounts.isEmpty {
                Section("Categories") {
                    ForEach(model.categoryCounts, id: \.name) { item in
                        HStack {
                            Label(item.name, systemImage: SoundCategories.symbol(for: item.name))
                            Spacer()
                            Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                        }
                        .tag("cat.\(item.name)")
                    }
                }
            }
            Section("Folders") {
                OutlineGroup(model.folderTree, children: \.children) { node in
                    HStack {
                        Label(node.name, systemImage: node.path.isEmpty ? "externaldrive" : "folder")
                        Spacer()
                        Text("\(node.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                    }
                    .tag(node.id)
                    .contextMenu {
                        if node.path.isEmpty, let root = model.roots.first(where: { $0.id == node.rootID }) {
                            Button("Reveal in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: root.path)) }
                            Button("Remove from Library", role: .destructive) { model.removeRoot(root) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { model.chooseFolder() } label: { Label("Add Folder…", systemImage: "plus") }
                Spacer()
                Button { model.showDuplicates = true } label: { Label("Duplicates", systemImage: "square.on.square") }
                    .help("Find copies of the same sound")
                    .disabled(model.samples.isEmpty)
            }
            .buttonStyle(.borderless).padding(10)
        }
    }
}
