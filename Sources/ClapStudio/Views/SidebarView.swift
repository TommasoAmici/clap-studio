import ClapCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    private var selection: Binding<String?> {
        Binding(
            get: { model.folderSelection ?? "smart.\(model.smartFilter.rawValue)" },
            set: { new in
                guard let new else { return }
                if new.hasPrefix("smart.") {
                    model.folderSelection = nil
                    model.smartFilter = SmartFilter(rawValue: String(new.dropFirst(6))) ?? .all
                } else {
                    model.smartFilter = .all
                    model.folderSelection = new
                }
            })
    }

    var body: some View {
        List(selection: selection) {
            Section("Filters") {
                ForEach(SmartFilter.allCases) { filter in
                    Label(filter.rawValue, systemImage: filter.symbol).tag("smart.\(filter.rawValue)")
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
            Button { model.chooseFolder() } label: { Label("Add Folder…", systemImage: "plus") }
                .buttonStyle(.borderless).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
