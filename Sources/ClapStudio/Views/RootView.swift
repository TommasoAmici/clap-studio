import ClapCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    #if DEBUG
    @State private var showInspector = ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_NO_INSPECTOR"] == nil
    #else
    @State private var showInspector = true
    #endif

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
                MelodyPanel()
                DrumPanel()
                if model.isInstallingUpdate {
                    UpdateInstallStatus()
                }
                StatusBar()
            }
            .frame(minWidth: 750)
            // The title would take room from the controls; the window keeps it for the Window menu.
            .modifier(HideToolbarTitle())
            .toolbar { MainToolbar() }
            .searchable(text: $model.searchText, placement: .toolbar,
                        prompt: model.textSearchAvailable ? "Search by name or describe a sound" : "Search by name")
            .modifier(SearchFocusRequests())
        }
        // Outside the split view, the inspector runs the window's full height, with its own toolbar section.
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
                .toolbar { ToolbarItem { InspectorToggle(isShown: $showInspector) } }
        }
        #if DEBUG
        .modifier(DebugSnapshotAccessibility())
        .task { await DebugSnapshot.runIfRequested(model: model) }
        #endif
        .onPreferenceChange(DropZoneFrames.self) { model.dropZones = $0 }
        .onDrop(of: [.fileURL], delegate: WindowDropDelegate(model: model))
        .sheet(isPresented: $model.showDuplicates) { DuplicatesSheet() }
        .sheet(isPresented: $model.showKit) { KitSheet() }
        .sheet(isPresented: $model.showExport, onDismiss: { model.exportIDs = nil }) { ExportSheet() }
        .sheet(isPresented: $model.showJoin, onDismiss: { model.joinSheetDismissed() }) { JoinSheet() }
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
            Button("Normalize", role: .destructive) { if let drive = model.normalizeRequest { model.normalizeUsb(drive) } }
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
            PoolBrowser(selection: selection, folder: [])
        case .poolFolder(let path):
            PoolBrowser(selection: selection, folder: path)
        }
    }
}

/// The Pool, or one folder of it, as a header over the sample list.
struct PoolBrowser: View {
    @Environment(AppModel.self) private var model
    let selection: UsbSelection
    let folder: [String]

    var body: some View {
        HStack {
            Label("Pool", systemImage: "tray.2").font(.headline)
            ForEach(Array(folder.enumerated()), id: \.offset) { _, name in
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                Text(name).font(.headline)
            }
            Text("on \(model.drive(id: selection.drive)?.name ?? "USB drive")").foregroundStyle(.secondary)
            Spacer()
            Button("Send Samples…") {
                model.openSquidExport(ids: model.actionTargets, drive: selection.drive, pool: true, poolFolder: folder.joined(separator: "/"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        Divider()
        LibraryTableView()
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

private struct UpdateInstallStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
                .accessibilityLabel(model.updateInstallMessage)
            Text(model.updateInstallMessage).lineLimit(1)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if model.isJoining {
                ProgressView().controlSize(.small)
                Text("Joining samples…")
                Button("Cancel") { model.cancelJoin() }.controlSize(.small)
            } else if let p = model.progress, model.isIndexing {
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
            VolumeControl()
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
