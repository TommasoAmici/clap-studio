import SwiftUI

/// The main column's toolbar: the view picker centered, as in Calendar, then the project and playback controls.
/// What doesn't fit moves to the system's overflow menu. The search field (`searchable`) and the inspector's toggle
/// follow, in the toolbar section over the inspector.
struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) { ViewPicker() }
        ToolbarItem { ProjectButton() }
        // The project button's text would otherwise read as part of the icon buttons beside it.
        if #available(macOS 26.0, *) { ToolbarSpacer(.fixed) }
        ToolbarItemGroup {
            ModelToggle("Drum Machine", systemImage: "square.grid.4x3.fill", isOn: \.showDrums,
                        help: "Show the drum machine")
            ModelToggle("Melody", systemImage: "pianokeys", isOn: \.showMelody,
                        help: "Show the melody: a piano roll that plays with the drum machine")
        }
        if #available(macOS 26.0, *) { ToolbarSpacer(.fixed) }
        ToolbarItemGroup {
            ModelToggle("Match Loudness", systemImage: "dial.medium", isOn: \.project.matchLoudness,
                        help: "Match preview loudness, so quiet and loud samples can be compared")
            ModelToggle("Autoplay", systemImage: "speaker.wave.2", isOn: \.autoplay,
                        help: "Play a sample when it is selected")
        }
    }
}

/// Library, Map or Places. Nothing is highlighted while a stick is showing; either choice leaves it.
private struct ViewPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("View", selection: Binding<ViewMode?>(get: { model.showingUsb ? nil : model.viewMode },
                                                     set: { if let mode = $0 { model.show(mode) } })) {
            ForEach(ViewMode.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }
        .pickerStyle(.segmented)
    }
}

/// A toolbar toggle for one of the model's settings. The title shows in the overflow menu.
private struct ModelToggle: View {
    @Environment(AppModel.self) private var model
    let title: String
    let systemImage: String
    let isOn: ReferenceWritableKeyPath<AppModel, Bool>
    let help: String

    init(_ title: String, systemImage: String, isOn: ReferenceWritableKeyPath<AppModel, Bool>, help: String) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.help = help
    }

    var body: some View {
        Toggle(isOn: Binding(get: { model[keyPath: isOn] }, set: { model[keyPath: isOn] = $0 })) {
            Label(title, systemImage: systemImage)
        }
        .help(help)
    }
}

/// Shows or hides the inspector. Declared in the inspector's content, it sits in the toolbar section over the
/// inspector.
struct InspectorToggle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isShown: Bool

    var body: some View {
        Button { withAnimation(reduceMotion ? nil : .default) { isShown.toggle() } } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
            .accessibilityValue(isShown ? "Shown" : "Hidden")
            .help(isShown ? "Hide the inspector" : "Show the inspector")
    }
}

/// Cmd+F focuses the search field (macOS 15 and later), expanding it first if the toolbar has collapsed it into a
/// button, as it does while the inspector is hidden.
struct SearchFocusRequests: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { FocusingContent(content: content, requests: model.searchFocusRequests) } else { content }
    }

    @available(macOS 15.0, *)
    private struct FocusingContent: View {
        let content: Content
        let requests: Int
        @FocusState private var focused: Bool

        var body: some View {
            content
                .searchFocused($focused)
                .onChange(of: requests) { focused = true }
        }
    }
}
