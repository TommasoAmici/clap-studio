import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SquidSettingsView()
                .tabItem { Label("Squid Salmple", systemImage: "externaldrive") }
            DeveloperSettingsView()
                .tabItem { Label("Developer", systemImage: "hammer") }
        }
        .frame(width: 520, height: 340)
    }
}
