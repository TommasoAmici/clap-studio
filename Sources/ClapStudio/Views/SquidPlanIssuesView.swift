import ClapCore
import SwiftUI

/// What the sheet has to say about where the samples go. A long list scrolls inside a fixed height, under a title that
/// says how many there are, so the rest of the sheet keeps its shape.
struct SquidPlanIssuesView: View {
    let issues: [SquidPlanIssue]
    /// Taller than this and the list scrolls.
    static let maxListHeight: CGFloat = 96
    @State private var contentHeight: CGFloat = 0

    private var tint: Color { issues.contains(where: \.isBlocking) ? .red : .orange }

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Warnings").font(.subheadline.bold())
                    Text("\(issues.count)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(tint, in: Capsule())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Warnings, \(issues.count)")
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            Text(issue.message).font(.caption).foregroundStyle(issue.isBlocking ? Color.red : Color.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(GeometryReader { Color.clear.preference(key: ListHeightKey.self, value: $0.size.height) })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, Self.maxListHeight))
                .onPreferenceChange(ListHeightKey.self) { contentHeight = $0 }
            }
        }
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
