import ClapCore
import SwiftUI

/// Settings > Sidebar: which sections the sidebar lists and in what order, as in Finder's sidebar preferences.
struct SidebarSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let order = model.sidebarLayout.order
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the sections the sidebar lists and drag them into the order you like. "
                 + "You can also right-click a section's title in the sidebar to move, fold or hide it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(order) { section in row(section, position: order.firstIndex(of: section) ?? 0, count: order.count) }
                    .onMove { model.sidebarLayout.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .border(Color(nsColor: .separatorColor))
            HStack {
                Text("A hidden section comes back when you tick it here.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { model.sidebarLayout.reset() }
                    .disabled(model.sidebarLayout.isDefault)
                    .help("List every section again, in the original order")
            }
        }
        .padding(20)
    }

    private func row(_ section: SidebarSection, position: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { !model.sidebarLayout.isHidden(section) },
                                 set: { model.setSidebar(section, hidden: !$0) })) {
                Text(section.title)
            }
            .toggleStyle(.checkbox)
            if let note = section.availabilityNote {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { move(section, from: position, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(position == 0).help("Move \(section.title) up").accessibilityLabel("Move \(section.title) up")
            Button { move(section, from: position, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(position == count - 1).help("Move \(section.title) down").accessibilityLabel("Move \(section.title) down")
        }
        .buttonStyle(.borderless).foregroundStyle(.primary)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move Up") { move(section, from: position, by: -1) }
        .accessibilityAction(named: "Move Down") { move(section, from: position, by: 1) }
        .contextMenu {
            Button("Move Up") { move(section, from: position, by: -1) }.disabled(position == 0)
            Button("Move Down") { move(section, from: position, by: 1) }.disabled(position == count - 1)
        }
    }

    /// One place up or down in the whole list, hidden sections included.
    private func move(_ section: SidebarSection, from position: Int, by step: Int) {
        guard (0..<model.sidebarLayout.order.count).contains(position + step) else { return }
        model.sidebarLayout.move(fromOffsets: IndexSet(integer: position), toOffset: step < 0 ? position - 1 : position + 2)
    }
}
