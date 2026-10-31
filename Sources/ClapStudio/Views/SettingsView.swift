import SwiftUI

/// The tabs of the Settings window. The one last used is remembered, and other views can open Settings on a given tab.
enum SettingsTab: String {
    case sidebar, birds, developer
    static let storageKey = "settings.tab"
}

struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var tabName = SettingsTab.sidebar.rawValue

    /// A tab that is not in this build (the birds tab in a commercial build) opens the sidebar tab instead.
    private var tab: Binding<SettingsTab> {
        Binding(get: {
            let saved = SettingsTab(rawValue: tabName) ?? .sidebar
            #if NON_COMMERCIAL
            return saved
            #else
            return saved == .birds ? .sidebar : saved
            #endif
        }, set: { tabName = $0.rawValue })
    }

    var body: some View {
        TabView(selection: tab) {
            SidebarSettingsView()
                .tabItem { Label("Sidebar", systemImage: "sidebar.left") }
                .tag(SettingsTab.sidebar)
            #if NON_COMMERCIAL
            BirdSettingsView()
                .tabItem { Label("Birds", systemImage: "bird") }
                .tag(SettingsTab.birds)
            #endif
            DeveloperSettingsView()
                .tabItem { Label("Developer", systemImage: "hammer") }
                .tag(SettingsTab.developer)
        }
        .frame(width: 520, height: 380)
    }
}
