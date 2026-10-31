import ClapCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    private var selection: Binding<String?> {
        Binding(get: { model.sidebarTag }, set: { if let new = $0 { model.selectSidebar(new) } })
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                ForEach(model.listedSidebarSections) { section in sectionView(section) }
            }
            .listStyle(.sidebar)
            .modifier(NoToolbarSeparator())
            Divider()
            HStack {
                Button { model.chooseFolder() } label: { Label("Add Folder…", systemImage: "plus") }
                Spacer()
                Button { model.showInsights = true } label: { Label("Ideas", systemImage: "lightbulb") }
                    .labelStyle(.iconOnly)
                    .help("Ideas: unused sounds similar to the ones you grab most")
                    .disabled(model.snapshot == nil)
                Button { model.showDuplicates = true } label: { Label("Duplicates", systemImage: "square.on.square") }
                    .labelStyle(.iconOnly)
                    .help("Find identical files")
                    .disabled(model.samples.isEmpty)
            }
            .buttonStyle(.borderless).padding(10)
        }
    }
}

extension SidebarView {
    /// One block of the sidebar. Order, folding and hiding are decided by `AppModel.sidebarLayout`.
    @ViewBuilder fileprivate func sectionView(_ section: SidebarSection) -> some View {
        switch section {
        case .filters:
            SidebarSectionBox(section: .filters) {
                ForEach(SmartFilter.allCases.filter { $0 != .hidden || model.hiddenCount > 0 }) { filter in
                    Label(filter.rawValue, systemImage: filter.symbol).tag("smart.\(filter.rawValue)")
                }
            }
        case .collections:
            CollectionsSidebarSection()
        case .categories:
            countedSection(.categories, items: model.categoryCounts, prefix: "cat.") { Label($0, systemImage: SoundCategories.symbol(for: $0)) }
        case .moods:
            countedSection(.moods, items: model.moodCounts, prefix: "mood.") { Label($0, systemImage: SoundMoods.symbol(for: $0)) }
        case .tags:
            countedSection(.tags, items: model.tagCounts, prefix: "tag.") { Label($0, systemImage: "number") }
        case .usbDrives:
            SquidSidebarSection()
        case .folders:
            SidebarSectionBox(section: .folders) {
                OutlineGroup(model.folderTree, children: \.children) { node in
                    HStack {
                        Label(node.name, systemImage: node.path.isEmpty ? "externaldrive" : "folder")
                        Spacer()
                        Text("\(node.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                    }
                    .tag(node.id)
                    .contextMenu {
                        if node.path.isEmpty, let root = model.roots.first(where: { $0.id == node.rootID }) {
                            Button("Rescan") { model.startIndexing(scanning: root) }.disabled(model.isIndexing)
                            Button("Reveal in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: root.path)) }
                            Button("Remove from Library", role: .destructive) { model.removeRoot(root) }
                        }
                    }
                }
            }
        }
    }

    /// A section of names with how many samples each holds (categories, moods, tags).
    private func countedSection<Row: View>(_ section: SidebarSection, items: [(name: String, count: Int)], prefix: String,
                                           @ViewBuilder label: @escaping (String) -> Row) -> some View {
        SidebarSectionBox(section: section) {
            ForEach(items, id: \.name) { item in
                HStack {
                    label(item.name)
                    Spacer()
                    Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                }
                .tag("\(prefix)\(item.name)")
            }
        }
    }
}

/// Long sidebars scrolled under the window buttons drew a black line through them: the toolbar's separator, which
/// appears whenever scrolled content sits beneath the toolbar. macOS 26 uses its native glass and scroll edge.
struct NoToolbarSeparator: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}
