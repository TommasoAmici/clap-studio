import AppKit
import ClapCore
import SwiftUI

extension SidebarSection {
    var title: String {
        switch self {
        case .filters: return "Filters"
        case .collections: return "Collections"
        case .categories: return "Categories"
        case .moods: return "Moods"
        case .tags: return "Tags"
        case .usbDrives: return "USB Drives"
        case .folders: return "Folders"
        }
    }

    /// Why a section may be missing from the sidebar even though it is not hidden.
    var availabilityNote: String? {
        switch self {
        case .categories, .moods, .tags: return "Listed once the library has some."
        case .usbDrives: return "Listed while a Squid Salmple drive is connected."
        case .filters, .collections, .folders: return nil
        }
    }
}

/// One section of the sidebar: it folds shut from its title (remembered between launches), and its title's context menu
/// moves it or hides it. The same choices are in Settings > Sidebar.
struct SidebarSectionBox<Content: View>: View {
    @Environment(AppModel.self) private var model
    let section: SidebarSection
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section(isExpanded: Binding(get: { !model.sidebarLayout.isCollapsed(section) },
                                    set: { model.sidebarLayout.setCollapsed(section, !$0) })) {
            content()
        } header: {
            Text(section.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu { SidebarSectionMenu(section: section) }
        }
    }
}

/// The right-click menu of a section's title.
struct SidebarSectionMenu: View {
    @Environment(AppModel.self) private var model
    let section: SidebarSection

    var body: some View {
        let listed = model.listedSidebarSections
        let position = listed.firstIndex(of: section)
        Button(model.sidebarLayout.isCollapsed(section) ? "Expand \(section.title)" : "Collapse \(section.title)") {
            model.sidebarLayout.setCollapsed(section, !model.sidebarLayout.isCollapsed(section))
        }
        Divider()
        Button("Move Up") { model.moveSidebar(section, by: -1) }.disabled(position == nil || position == 0)
        Button("Move Down") { model.moveSidebar(section, by: 1) }.disabled(position == nil || position == listed.count - 1)
        Divider()
        Button("Hide \(section.title)") { model.setSidebar(section, hidden: true) }
        let hidden = SidebarSection.allCases.filter { model.sidebarLayout.isHidden($0) }
        if !hidden.isEmpty {
            Menu("Show Hidden Section") {
                ForEach(hidden) { other in Button(other.title) { model.setSidebar(other, hidden: false) } }
            }
        }
        Divider()
        Button("Sidebar Settings…") {
            UserDefaults.standard.set(SettingsTab.sidebar.rawValue, forKey: SettingsTab.storageKey)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
