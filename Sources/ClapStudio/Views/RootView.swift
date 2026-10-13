import ClapCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if let usb = model.usbSelection, model.showingUsb {
                    UsbBrowser(selection: usb)
                } else if model.roots.isEmpty {
                    OnboardingView()
                } else {
                    FilterBar()
                    switch model.viewMode {
                    case .library: LibraryTableView()
                    case .map: MapPanel()
                    case .places: PlacesPanel()
                    }
                }
                DrumPanel()
                StatusBar()
            }
            // The controls sit at the right end of the toolbar, the search box beside the inspector toggle. They
            // are drawn at one height (`ToolbarMetrics`).
            .frame(minWidth: 750)
            // The title would take room from the controls; the window keeps it for the Window menu.
            .modifier(HideToolbarTitle())
            .toolbar {
                // Attached to the main content, before the inspector, so they stay above it and never slide under
                // the inspector column; the stretch pushes them to its right end.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        // Nothing is highlighted while a stick is showing; either choice leaves it.
                        ToolbarSegments(choices: ViewMode.allCases.map { ($0.rawValue, $0) },
                                        selection: model.showingUsb ? nil : model.viewMode) { model.show($0) }
                        ProjectButton()
                        ToolbarIconButton(isOn: model.project.matchLoudness, action: { model.project.matchLoudness.toggle() }) {
                            Image(systemName: "dial.medium")
                        }
                        .help("Match preview loudness, so quiet and loud samples can be compared")
                        ToolbarIconButton(isOn: model.showDrums, action: { model.showDrums.toggle() }) { Image(systemName: "square.grid.4x3.fill") }
                            .help("Show the drum machine")
                        ToolbarIconButton(isOn: model.autoplay, action: { model.autoplay.toggle() }) { Image(systemName: "speaker.wave.2") }
                            .help("Play a sample when it is selected")
                    }
                    .frame(maxWidth: .infinity)
                }
                ToolbarItem(placement: .primaryAction) { SearchField() }
                ToolbarItem(placement: .primaryAction) {
                    ToolbarIconButton(action: { showInspector.toggle() }) { Image(systemName: "sidebar.trailing") }
                        .help(showInspector ? "Hide the inspector" : "Show the inspector")
                }
            }
            .inspector(isPresented: $showInspector) {
                InspectorView()
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
            }
        }
        #if DEBUG
        .task { await DebugSnapshot.runIfRequested(model: model) }
        #endif
        .onPreferenceChange(DropZoneFrames.self) { model.dropZones = $0 }
        .onDrop(of: [.fileURL], delegate: WindowDropDelegate(model: model))
        .sheet(isPresented: $model.showDuplicates) { DuplicatesSheet() }
        .sheet(isPresented: $model.showKit) { KitSheet() }
        .sheet(isPresented: $model.showExport, onDismiss: { model.exportIDs = nil }) { ExportSheet() }
        .sheet(isPresented: $model.showInsights) { InsightsSheet() }
        .sheet(isPresented: $model.showSquidExport) { SquidExportSheet() }
        .onKeyPress(.space) {
            guard !isTypingInTextField else { return .ignored }
            model.togglePlayback()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isTypingInTextField else { return .ignored }
            guard model.selectedID != nil else { return .ignored }
            model.sweep(1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !isTypingInTextField else { return .ignored }
            guard model.selectedID != nil else { return .ignored }
            model.sweep(-1)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "f")) { _ in
            guard !isTypingInTextField else { return .ignored }
            guard !model.actionTargets.isEmpty else { return .ignored }
            model.toggleFavorite(model.actionTargets)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "m")) { _ in
            guard !isTypingInTextField else { return .ignored }
            guard model.selectedID != nil else { return .ignored }
            model.addCueAtMarker()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard !isTypingInTextField else { return .ignored }
            guard let n = Int(press.characters) else { return .ignored }
            model.playCue(number: n)
            return .handled
        }
        .modifier(NewCollectionPrompt())
        .modifier(AddTagPrompt())
        .modifier(WriteTagsPrompt())
        .alert("Normalize all samples on \(model.normalizeRequest?.name ?? "the drive")?",
               isPresented: Binding(get: { model.normalizeRequest != nil }, set: { if !$0 { model.normalizeRequest = nil } })) {
            Button("Normalize") { if let drive = model.normalizeRequest { model.normalizeUsb(drive) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every WAV in the ALM022 folder (banks and Pool) is brought to the same loudness, with peaks kept below -1 dB. "
                 + "The files on the drive are changed in place and this cannot be undone; the audio is not otherwise altered.")
        }
        .alert("Clap Studio", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

/// What the main area shows for a place on a stick: the banks of a set, or the Pool as a plain list.
struct UsbBrowser: View {
    @Environment(AppModel.self) private var model
    let selection: UsbSelection

    var body: some View {
        switch selection.area {
        case .set(let name):
            SquidSetView(selection: selection, setName: name)
        case .bank(let set, let number):
            SquidSetView(selection: selection, setName: set, onlyBank: number)
        case .pool:
            HStack {
                Label("Pool", systemImage: "tray.2").font(.headline)
                Text("on \(model.drive(id: selection.drive)?.name ?? "USB drive")").foregroundStyle(.secondary)
                Spacer()
                Button("Send Samples…") { model.openSquidExport(ids: model.actionTargets, drive: selection.drive, pool: true) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            LibraryTableView()
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Point Clap Studio at your sample folder").font(.title2)
            Text("Samples are indexed in place. Your files are never moved, renamed or changed.")
                .foregroundStyle(.secondary)
            Button("Choose Folder…") { model.chooseFolder() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if let p = model.progress, model.isIndexing {
                ProgressView(value: p.fraction).frame(width: 160)
                Text("Indexed \(p.done) of \(p.total)").monospacedDigit()
                if !p.currentName.isEmpty { Text(p.currentName).lineLimit(1).foregroundStyle(.secondary) }
                Button("Stop") { model.cancelIndexing() }.controlSize(.small)
            } else if model.isIndexing {
                ProgressView().controlSize(.small)
                Text(model.statusMessage)
            } else {
                Text("\(model.samples.count) samples").monospacedDigit()
                if model.failedCount > 0 { Text("· \(model.failedCount) unreadable").foregroundStyle(.secondary) }
            }
            // The rows picked in the list, or the dots picked on the map (shift-drag), whichever is showing.
            let picked = model.viewMode == .map ? model.mapSelection.count : model.tableSelection.count
            if picked > 1 {
                Text("· \(picked) selected").monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            if let name = model.undoName {
                Button("Undo \(name)") { model.undoLibraryEdit() }
                    .buttonStyle(.borderless).controlSize(.small).lineLimit(1)
            }
            if model.usingFallbackModel {
                Label("Basic similarity (no neural model)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).help(model.modelNote)
            }
            // The drum machine's buttons and the volume trade places while the drum machine is open.
            if model.showDrums { DrumActions() } else { VolumeControl() }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

/// Takes the window title out of the toolbar (macOS 15 and later), where it claims room the controls need.
private struct HideToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.toolbar(removing: .title) } else { content }
    }
}
