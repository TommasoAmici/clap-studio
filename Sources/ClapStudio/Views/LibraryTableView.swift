import AppKit
import ClapCore
import SwiftUI

struct LibraryTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LibraryList(model: model, revision: model.visibleRevision, selection: model.tableSelection,
                    sortOrder: model.sortOrder, drumTracks: model.drumTracks, segmentMatches: model.segmentMatches,
                    shuffleSeed: model.shuffleSeed)
            .overlay {
                if model.visible.isEmpty {
                    if model.searchPending {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    } else if !model.isIndexing {
                        ContentUnavailableView(model.samples.isEmpty ? "No samples yet" : "No matches",
                                               systemImage: "magnifyingglass")
                    }
                }
            }
            .overlay(alignment: .top) {
                // The previous results stay put until the new ones are ready.
                if model.searchPending && !model.visible.isEmpty { SearchingBadge().padding(.top, 34) }
            }
    }
}

struct SearchingBadge: View {
    var body: some View {
        Label {
            Text("Searching…")
        } icon: {
            ProgressView().controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .allowsHitTesting(false)
    }
}

struct UsageBadge: View {
    let count: Int
    var body: some View {
        if count == 0 {
            Text("–").foregroundStyle(.tertiary)
        } else {
            Text("\(count)×").monospacedDigit().padding(.horizontal, 6)
                .background(Color.orange.opacity(min(0.15 + Double(count) * 0.05, 0.6)), in: Capsule())
        }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        if seconds < 10 { return String(format: "%.2fs", seconds) }
        let h = Int(seconds) / 3600, m = Int(seconds) / 60 % 60, s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return m > 0 ? String(format: "%d:%02d", m, s) : String(format: "%.1fs", seconds)
    }

    /// A position in a recording: "2:05", or "1:02:05" past an hour.
    static func timestamp(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func clock(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%d:%02d.%03d", ms / 60000, ms / 1000 % 60, ms % 1000)
    }

    static func date(_ ts: Double?) -> String {
        guard let ts else { return "never" }
        return Date(timeIntervalSince1970: ts).formatted(.relative(presentation: .named))
    }
}
