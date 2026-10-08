import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SquidSettingsView()
                .tabItem { Label("Squid Salmple", systemImage: "externaldrive") }
            #if NON_COMMERCIAL
            BirdSettingsView()
                .tabItem { Label("Birds", systemImage: "bird") }
            #endif
            DeveloperSettingsView()
                .tabItem { Label("Developer", systemImage: "hammer") }
        }
        .frame(width: 520, height: 380)
    }
}
