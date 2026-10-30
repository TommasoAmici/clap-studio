import AppKit
import ClapCore
import SwiftUI

/// A warning (orange triangle) next to a name the module may not read as written; hovering explains the rules.
/// A name a folder cannot have shows a red mark instead, since that one cannot be saved.
struct NameIssueIcon: View {
    let report: SquidNameReport

    var body: some View {
        if !report.isClean {
            Image(systemName: report.isBlocked ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.isBlocked ? Color.red : Color.orange)
                .help(report.message)
                .accessibilityLabel(report.isBlocked ? "Name cannot be used" : "Name warning")
                .accessibilityHint(report.message)
        }
    }
}

/// How many channels a bank still has free. The orange is light in dark mode, so the number is dark there
/// (white on it was hard to read); in light mode the orange is deep and the number stays white.
struct FreeSlotsBadge: View {
    let count: Int
    var horizontalPadding: CGFloat = 5
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("\(count)").font(.caption2.bold()).monospacedDigit()
            .foregroundStyle(colorScheme == .dark ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, horizontalPadding).padding(.vertical, 1)
            .background(Color.orange, in: Capsule())
            .help(count == 1 ? "Room for 1 more sample" : "Room for \(count) more samples")
            .accessibilityLabel(count == 1 ? "1 free slot" : "\(count) free slots")
    }
}

/// A name edited in place, like renaming in Finder: Return keeps it, Escape cancels, clicking away keeps it.
/// The text is never changed for the user; the icon says what is wrong with it.
struct SquidRenameField: View {
    let initial: String
    var placeholder = "Name"
    let report: (String) -> SquidNameReport
    let commit: (String) -> Void
    let cancel: () -> Void

    @State private var draft = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { finish(save: true, blurred: false) }
                .onExitCommand { finish(save: false, blurred: false) }
            NameIssueIcon(report: report(draft))
        }
        .task {
            draft = initial
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { finish(save: true, blurred: true) } }
    }

    private func finish(save: Bool, blurred: Bool) {
        guard !finished else { return }
        if !save || draft == initial { finished = true; cancel(); return }
        if report(draft).isBlocked {
            if blurred { finished = true; cancel() }      // Return keeps the field open so the problem can be fixed
            return
        }
        finished = true
        commit(draft)
    }
}
