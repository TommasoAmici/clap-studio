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
        Window("Clap Studio", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1250, minHeight: 680)
                .task {
                    if model.store == nil { model.bootstrap() }
                    model.startUpdateChecks()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { model.checkForUpdates(manual: true) }
                    .disabled(model.isCheckingUpdates || model.isInstallingUpdate)
            }
            SidebarCommands()
            InspectorCommands()
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Library") { model.show(.library) }.keyboardShortcut("1")
                Button("Map") { model.show(.map) }.keyboardShortcut("2")
                Button("Places") { model.show(.places) }.keyboardShortcut("3")
                Divider()
                Toggle("Show Effects", isOn: $model.showEffects)
                Toggle("Show Drum Machine", isOn: $model.showDrums)
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Toggle("Show Melody", isOn: $model.showMelody)
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Divider()
                Button("Shuffle Library") { model.shuffleList() }.keyboardShortcut("r")
                    .disabled(model.viewMode != .library || !model.canShuffle)
                Divider()
                Button("Ideas…") { model.showInsights = true }
                    .disabled(model.snapshot == nil)
                Button("Find Duplicates…") { model.showDuplicates = true }
                    .disabled(model.samples.isEmpty)
            }
            CommandGroup(after: .undoRedo) {
                Button(model.undoName.map { "Undo \($0)" } ?? "Undo Library Change") { model.undoLibraryEdit() }
                    .keyboardShortcut("z", modifiers: [.command, .option]).disabled(model.undoName == nil)
                Button(model.redoName.map { "Redo \($0)" } ?? "Redo Library Change") { model.redoLibraryEdit() }
                    .keyboardShortcut("z", modifiers: [.command, .option, .shift]).disabled(model.redoName == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    if #available(macOS 15.0, *) { model.searchFocusRequests += 1 } else { SearchFocus.focus() }
                }
                    .keyboardShortcut("f")
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("New Collection…") { model.newCollectionSeed = model.actionTargets }
                    .keyboardShortcut("n")
                Divider()
                Button("Open MIDI File…") { model.chooseMidiFile() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Open Drum MIDI File…") { model.chooseMidiFile(forDrums: true) }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Divider()
                Button("Copy To…") { model.openExport(ids: model.actionTargets) }
                    .keyboardShortcut("e")
                    .disabled(model.actionTargets.isEmpty)
                if model.squidEnabled {
                    Button("Send to Squid…") { model.openSquidExport(ids: model.actionTargets) }
                        .disabled(model.actionTargets.isEmpty)
                }
                Button("Reveal in Finder") {
                    let urls = model.actionTargets.compactMap { model.sampleByID[$0]?.url }
                    if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                }
                .keyboardShortcut("r", modifiers: [.command, .control])
                .disabled(model.actionTargets.isEmpty)
                Divider()
                Button("Rescan Library") { model.startIndexing() }.keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.isIndexing || model.roots.isEmpty)
            }
            CommandMenu("Sample") {
                Button(model.playback.sampleID != nil ? "Stop Preview" : "Play Preview") { model.togglePlayback() }
                    .disabled(model.selectedID == nil && model.playback.sampleID == nil)
                Button("Previous Similar Sound") { model.sweep(-1) }
                    .disabled(model.selectedID == nil)
                Button("Next Similar Sound") { model.sweep(1) }
                    .disabled(model.selectedID == nil)
                Divider()
                Button("Find Similar Sounds") { if let id = model.selectedID { model.showSimilar(to: id) } }
                    .disabled(model.selectedID == nil)
                Button("Build a Kit From This…") { if let id = model.selectedID { model.buildKit(around: id) } }
                    .disabled(model.selectedID == nil)
                Button("VST3 Effects…") { model.openEffects(ids: model.effectsActionTargets) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(model.effectsActionTargets.isEmpty)
                Button("Join Samples…") { model.openJoin(ids: model.joinActionTargets) }
                    .keyboardShortcut("j", modifiers: [.command, .option])
                    .disabled(model.joinActionTargets.count < 2 || model.isJoining)
                Button("Add to Drum Machine") { model.addToDrums(model.actionTargets) }
                    .disabled(model.actionTargets.isEmpty || model.drumPattern.isFull)
                Button("Add to Melody") { model.addToMelody(model.actionTargets) }
                    .disabled(model.actionTargets.isEmpty || model.melodyPattern.tracks.count >= 4)
                Divider()
                let targets = model.actionTargets.compactMap { model.sampleByID[$0] }
                Button(!targets.isEmpty && targets.allSatisfy(\.favorite) ? "Remove from Favorites" : "Add to Favorites") {
                    model.toggleFavorite(model.actionTargets)
                }
                .disabled(model.actionTargets.isEmpty)
                Button("Add Tag…") { model.tagPromptTargets = model.actionTargets }
                    .disabled(model.actionTargets.isEmpty)
                Button("Use Keywords as Tags") { model.importFileKeywords(model.actionTargets) }
                    .disabled(model.actionTargets.isEmpty)
                Button("Add Cue at Marker") { model.addCueAtMarker() }
                    .disabled(model.selectedID == nil)
                Divider()
                Button(!targets.isEmpty && targets.allSatisfy(\.hidden) ? "Show in Library Again" : "Hide from Library") {
                    if !targets.isEmpty && targets.allSatisfy(\.hidden) { model.unhide(model.actionTargets) }
                    else { model.hide(model.actionTargets) }
                }
                .disabled(model.actionTargets.isEmpty)
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}
