import AppKit
import SwiftUI

@main
struct ClapStudioApp: App {
    @State private var model = AppModel()

    init() {
        // Lets `swift run` launch a regular, focusable app without an app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        AppIconSwitcher.start()
    }

    var body: some Scene {
        WindowGroup("Clap Studio") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 680)
                .task { if model.store == nil { model.bootstrap() } }
        }
        .commands {
            CommandGroup(after: .undoRedo) {
                Button(model.undoName.map { "Undo \($0)" } ?? "Undo Library Change") { model.undoLibraryEdit() }
                    .keyboardShortcut("z", modifiers: [.command, .option]).disabled(model.undoName == nil)
                Button(model.redoName.map { "Redo \($0)" } ?? "Redo Library Change") { model.redoLibraryEdit() }
                    .keyboardShortcut("z", modifiers: [.command, .option, .shift]).disabled(model.redoName == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") { if !SearchFocus.focus() { model.searchFocusRequests += 1 } }
                    .keyboardShortcut("f")
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("Rescan Library") { model.startIndexing() }.keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.isIndexing || model.roots.isEmpty)
                Button("Shuffle Library") { model.shuffleList() }.keyboardShortcut("r")
                    .disabled(model.viewMode != .library || !model.canShuffle)
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}
