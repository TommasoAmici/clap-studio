import ClapCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    #if DEBUG
    @State private var showInspector = ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_NO_INSPECTOR"] == nil
    #else
    @State private var showInspector = true
    #endif
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var mainWidth: CGFloat = 750
    @State private var settleTask: Task<Void, Never>?

    /// The width of the toolbar's controls: the main column, less a margin and, with the inspector hidden, room for
    /// its toggle. Made wider than the column, the toolbar would drop them for good, so while the inspector opens or
    /// closes, either one (the column's width is changing, and the measurement is behind) they take a width that fits whatever
    /// the column's width, which is never under `ToolbarLayout.narrowest`.
    private var controlsWidth: CGFloat {
        guard settleTask == nil else { return ToolbarLayout.safeWidth }
        return max(mainWidth - ToolbarLayout.margin - (showInspector ? 0 : ToolbarLayout.inspectorToggle), 0)
    }

    /// Called as a sidebar opens or closes.
    private func columnsChanging() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { settleTask = nil }
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
                .modifier(HideSidebarToggle())
                .toolbar { ToolbarItem(placement: .automatic) { SidebarToggle(columns: $columns) } }
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
            // The toolbar's controls are the system's, at their large size, so they follow the system's appearance
            // settings.
            .frame(minWidth: ToolbarLayout.narrowest)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { mainWidth = $0 }
            // The title would take room from the controls; the window keeps it for the Window menu.
            .modifier(HideToolbarTitle())
            .toolbar {
                // The system puts this item at the main column's left, after the sidebar; made as wide as the column,
                // it keeps the controls there and the search box at the column's right, just before the inspector.
                ToolbarItem(placement: .navigation) { ToolbarControls().frame(width: controlsWidth) }
                if #available(macOS 26.0, *) { ToolbarSpacer(.flexible) }
                ToolbarItem(placement: .primaryAction) { InspectorToggle(isShown: $showInspector) }
            }
            .onChange(of: showInspector) { columnsChanging() }
            .onChange(of: columns) { columnsChanging() }
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


private struct HideSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.toolbar(removing: .sidebarToggle) } else { content }
    }
}

/// The view picker, the toggles and the search box, filling the main column's toolbar; the system's controls at
/// their large size.
private struct ToolbarControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            // Nothing is highlighted while a stick is showing; either choice leaves it.
            Picker("View", selection: Binding<ViewMode?>(get: { model.showingUsb ? nil : model.viewMode },
                                                         set: { if let mode = $0 { model.show(mode) } })) {
                ForEach(ViewMode.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            ProjectButton()
            Toggle(isOn: $model.project.matchLoudness) { Image(systemName: "dial.medium") }
                .help("Match preview loudness, so quiet and loud samples can be compared")
            Toggle(isOn: $model.showDrums) { Image(systemName: "square.grid.4x3.fill") }
                .help("Show the drum machine")
            Toggle(isOn: $model.autoplay) { Image(systemName: "speaker.wave.2") }
                .help("Play a sample when it is selected")
            Spacer(minLength: 0)
            SearchField()
        }
        .toggleStyle(.button)
        .controlSize(.large)
    }
}

/// Shows or hides the sidebar; drawn like the other toolbar buttons, which the system's own toggle isn't.
private struct SidebarToggle: View {
    @Binding var columns: NavigationSplitViewVisibility

    var body: some View {
        Button { withAnimation { columns = columns == .detailOnly ? .all : .detailOnly } } label: { Image(systemName: "sidebar.leading") }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(columns == .detailOnly ? "Show the sidebar" : "Hide the sidebar")
    }
}

/// Shows or hides the inspector.
private struct InspectorToggle: View {
    @Binding var isShown: Bool

    var body: some View {
        Button { withAnimation { isShown.toggle() } } label: { Image(systemName: "sidebar.trailing") }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(isShown ? "Hide the inspector" : "Show the inspector")
    }
}

/// What the toolbar's controls are laid out by.
private enum ToolbarLayout {
    /// The narrowest the main column gets.
    static let narrowest: CGFloat = 750
    /// Left over beside the controls so they sit as far from the inspector as from the sidebar.
    static let margin: CGFloat = 15
    /// What the inspector's toggle takes in the main column while the inspector is hidden.
    static let inspectorToggle: CGFloat = 70
    /// A width that fits in the main column in either case.
    static let safeWidth = narrowest - margin - inspectorToggle
}
