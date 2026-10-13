import SwiftUI

/// The search box in the toolbar, next to the inspector toggle. Cmd+F focuses it.
struct SearchField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

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
        .frame(minWidth: 120, idealWidth: 160, maxWidth: 240)
        .frame(height: ToolbarMetrics.height)
        .background(ToolbarMetrics.fill, in: RoundedRectangle(cornerRadius: ToolbarMetrics.corner))
        .onChange(of: model.searchFocusRequests) { focused = true }
    }
}
