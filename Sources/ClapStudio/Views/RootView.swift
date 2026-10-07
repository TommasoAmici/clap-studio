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
                if model.roots.isEmpty {
                    OnboardingView()
                } else {
                    switch model.viewMode {
                    case .library: LibraryTableView()
                    case .map: MapPanel()
                    }
                }
                StatusBar()
            }
            .inspector(isPresented: $showInspector) {
                InspectorView().inspectorColumnWidth(min: 300, ideal: 360, max: 480)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $model.viewMode) {
                        ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItem {
                    Toggle(isOn: $model.autoplay) { Image(systemName: "speaker.wave.2") }
                        .help("Play a sample when it is selected")
                }
                ToolbarItem {
                    Button { showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                        .help("Show or hide the inspector")
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search samples")
        .onKeyPress(.space) {
            model.togglePlayback()
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "m")) { _ in
            guard model.selectedID != nil else { return .ignored }
            model.addCueAtPlayhead()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let n = Int(press.characters) else { return .ignored }
            model.playCue(number: n)
            return .handled
        }
        .alert("Clap Studio", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
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
            Spacer()
            if model.usingFallbackModel {
                Label("Basic similarity (no neural model)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).help(model.modelNote)
            }
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill").imageScale(.small)
                Slider(value: Binding(get: { Double(model.volume) }, set: { model.volume = Float($0) }), in: 0...1)
                    .frame(width: 90).controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}
