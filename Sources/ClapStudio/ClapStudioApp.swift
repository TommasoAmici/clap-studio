import AppKit
import SwiftUI

@main
struct ClapStudioApp: App {
    @State private var model = AppModel()

    init() {
        // Lets `swift run` launch a regular, focusable app without an app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Clap Studio") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 680)
                .task { if model.store == nil { model.bootstrap() } }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("Rescan Library") { model.startIndexing() }.keyboardShortcut("r")
                    .disabled(model.isIndexing || model.roots.isEmpty)
            }
        }
    }
}
