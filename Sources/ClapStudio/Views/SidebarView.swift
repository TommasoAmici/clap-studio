import ClapCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: CollectionRecord?
    @State private var renameText = ""

    private var selection: Binding<String?> {
        Binding(get: { model.sidebarTag }, set: { if let new = $0 { model.selectSidebar(new) } })
    }

    var body: some View {
        List(selection: selection) {
            Section("Filters") {
                ForEach(SmartFilter.allCases.filter { $0 != .hidden || model.hiddenCount > 0 }) { filter in
                    Label(filter.rawValue, systemImage: filter.symbol).tag("smart.\(filter.rawValue)")
                }
            }
            Section("Collections") {
                ForEach(model.collections) { collection in
                    HStack {
                        Label(collection.name, systemImage: "rectangle.stack")
                        Spacer()
                        Text("\(collection.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                    }
                    .tag("col.\(collection.id)")
                    .contextMenu {
                        Button("Rename…") { renaming = collection; renameText = collection.name }
                        Button("Delete Collection", role: .destructive) { model.delete(collection: collection.id) }
                    }
                }
                Button { model.newCollectionSeed = [] } label: { Label("New Collection", systemImage: "plus") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
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
            if !model.moodCounts.isEmpty {
                Section("Moods") {
                    ForEach(model.moodCounts, id: \.name) { item in
                        HStack {
                            Label(item.name, systemImage: SoundMoods.symbol(for: item.name))
                            Spacer()
                            Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                        }
                        .tag("mood.\(item.name)")
                    }
                }
            }
            if !model.tagCounts.isEmpty {
                Section("Tags") {
                    ForEach(model.tagCounts, id: \.name) { item in
                        HStack {
                            Label(item.name, systemImage: "number")
                            Spacer()
                            Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                        }
                        .tag("tag.\(item.name)")
                    }
                }
            }
            if model.squidEnabled { SquidSidebarSection() }
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
        .modifier(NoToolbarSeparator())
        .alert("Rename Collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let renaming { model.rename(collection: renaming.id, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { model.chooseFolder() } label: { Label("Add Folder…", systemImage: "plus") }
                Spacer()
                Button { model.showInsights = true } label: { Label("Ideas", systemImage: "lightbulb") }
                    .labelStyle(.iconOnly)
                    .help("Ideas: unused sounds similar to the ones you grab most")
                    .disabled(model.snapshot == nil)
                Button { model.showDuplicates = true } label: { Label("Duplicates", systemImage: "square.on.square") }
                    .labelStyle(.iconOnly)
                    .help("Find duplicates")
                    .disabled(model.samples.isEmpty)
            }
            .buttonStyle(.borderless).padding(10)
        }
    }
}

/// Long sidebars scrolled under the window buttons drew a black line through them: the toolbar's separator, which
/// appears whenever scrolled content sits beneath the toolbar. The sidebar has no use for it.
struct NoToolbarSeparator: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar) } else { content }
    }
}
