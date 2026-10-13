import SwiftUI

/// The toolbar's controls, drawn to one height so the view picker, the buttons and the search box line up.
enum ToolbarMetrics {
    static let height: CGFloat = 28
    static let corner: CGFloat = 8
    static var fill: some ShapeStyle { Color.primary.opacity(0.07) }
}

/// A segmented choice as tall as the other toolbar controls (the system one is shorter).
struct ToolbarSegments<Value: Hashable>: View {
    let choices: [(title: String, value: Value)]
    let selection: Value?
    let onSelect: (Value) -> Void
    var width: CGFloat = 210

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                let selected = choice.value == selection
                Text(choice.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(selected ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: ToolbarMetrics.corner - 2))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(choice.value) }
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .frame(width: width, height: ToolbarMetrics.height)
        .background(ToolbarMetrics.fill, in: RoundedRectangle(cornerRadius: ToolbarMetrics.corner))
    }
}

/// A button for the toolbar; lit when `isOn`.
struct ToolbarIconButton<Label: View>: View {
    var isOn = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 7)
                .frame(minWidth: ToolbarMetrics.height, minHeight: ToolbarMetrics.height)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: ToolbarMetrics.corner))
                .contentShape(RoundedRectangle(cornerRadius: ToolbarMetrics.corner))
        }
        .buttonStyle(.plain)
    }
}
