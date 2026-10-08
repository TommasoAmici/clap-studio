import SwiftUI

/// The search box in the toolbar, centred over the main area with the other toolbar controls. Cmd+F focuses it.
struct SearchField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    private static let height: CGFloat = 28

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.textSearchAvailable ? "Search by name or describe a sound" : "Search by name",
                      text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { model.searchText = ""; focused = false }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 140, idealWidth: 180, maxWidth: 240)
        .frame(height: Self.height)        // as tall as the other toolbar controls
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: model.searchFocusRequests) { focused = true }
    }
}
