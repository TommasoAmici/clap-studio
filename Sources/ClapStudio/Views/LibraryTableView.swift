import AppKit
import ClapCore
import SwiftUI

struct LibraryTableView: View {
    @Environment(AppModel.self) private var model
    /// Which columns are shown and in what order. Right-click a column heading to change it; remembered between runs.
    @SceneStorage("libraryColumns") private var columns: TableColumnCustomization<SampleRecord>

    var body: some View {
        @Bindable var model = model
        let selection = Binding<Set<Int64>>(get: { model.tableSelection }, set: { new in
            if new.count == 1 { model.select(new.first, play: true) } else { model.tableSelection = new }
        })

        Table(model.visible, selection: selection, sortOrder: $model.sortOrder, columnCustomization: $columns) {
            nameColumn
            measureColumns
            extraColumns
        }
        .id(model.shuffleSeed ?? 0)      // a new order starts at the top of the list
        .contextMenu(forSelectionType: Int64.self) { ids in
            SampleMenuContent(entries: model.sampleMenu(for: Array(ids)))
        } primaryAction: { ids in
            if let id = ids.first { model.select(id, play: true) }
        }
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

    /// The name cell is a drag source (for dropping into a DAW). A drag source swallows the click that would
    /// normally select the row, so it selects and previews explicitly.
    @TableColumnBuilder<SampleRecord, KeyPathComparator<SampleRecord>>
    private var nameColumn: some TableColumnContent<SampleRecord, KeyPathComparator<SampleRecord>> {
        TableColumn("Name", value: \.name) { s in
            HStack(spacing: 6) {
                if let track = model.drumTracks[s.id] {
                    Image(systemName: "circle.grid.3x3.fill").foregroundStyle(.orange)
                        .help("Loaded in the drum machine (track \(track))")
                } else {
                    Image(systemName: "waveform").foregroundStyle(.secondary)
                }
                Text(s.name).lineLimit(1)
                if let match = model.segmentMatches[s.id] {
                    Text("at \(Format.timestamp(match.start))").font(.caption2).monospacedDigit()
                        .padding(.horizontal, 5).background(Color.accentColor.opacity(0.18), in: Capsule())
                        .help("Best match in this recording")
                }
                if s.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                if s.status == .pending { ProgressView().controlSize(.mini) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.drumTracks[s.id] == nil ? Color.clear : Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture {
                model.select(s.id, play: true)
                focusTableUnderClick()
            }
            .sampleDrag(s, model: model)
        }
        .width(min: 180, ideal: 260)
        .customizationID("name")
        .disabledCustomizationBehavior(.visibility)      // a list of nameless rows would be useless
    }

    @TableColumnBuilder<SampleRecord, KeyPathComparator<SampleRecord>>
    private var measureColumns: some TableColumnContent<SampleRecord, KeyPathComparator<SampleRecord>> {
        TableColumn("Length", value: \.duration) { s in
            Text(Format.duration(s.duration)).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(60)
        .customizationID("length")
        TableColumn("BPM", value: \.bpmSort) { s in
            Text(s.bpmText).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(52)
        .customizationID("bpm")
        TableColumn("Key", value: \.keySort) { s in
            Text(s.keyName ?? "").foregroundStyle(.secondary).lineLimit(1)
        }
        .width(min: 40, ideal: 72)
        .customizationID("key")
        TableColumn("Level", value: \.levelSort) { s in
            Text(s.levelText).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(62)
        .customizationID("level")
        TableColumn("Bright", value: \.brightnessSort) { s in
            Text(s.brightnessText).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(64)
        .customizationID("bright")
        TableColumn("Category", value: \.categorySort) { s in
            Text(s.effectiveCategory ?? "").foregroundStyle(.secondary).lineLimit(1)
        }
        .width(min: 60, ideal: 90)
        .customizationID("category")
        TableColumn("Mood", value: \.moodText) { s in
            Text(s.moodText).foregroundStyle(.secondary).lineLimit(1)
        }
        .width(min: 60, ideal: 110)
        .customizationID("mood")
        TableColumn("Cues", value: \.cueCount) { s in
            Text(s.cueCount == 0 ? "" : "\(s.cueCount)").monospacedDigit().foregroundStyle(.secondary)
        }
        .width(44)
        .customizationID("cues")
        TableColumn("Uses", value: \.useCount) { s in
            UsageBadge(count: s.useCount)
        }
        .width(56)
        .customizationID("uses")
    }

    /// Columns that are not shown until chosen from the heading's menu.
    @TableColumnBuilder<SampleRecord, KeyPathComparator<SampleRecord>>
    private var extraColumns: some TableColumnContent<SampleRecord, KeyPathComparator<SampleRecord>> {
        TableColumn("Tags", value: \.tagsText) { s in
            Text(s.tagsText).foregroundStyle(.secondary).lineLimit(1)
        }
        .width(min: 60, ideal: 120)
        .customizationID("tags")
        .defaultVisibility(.hidden)
        TableColumn("Folder", value: \.folder) { s in
            Text(s.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
        .width(min: 60, ideal: 140)
        .customizationID("folder")
        .defaultVisibility(.hidden)
        TableColumn("Format", value: \.formatText) { s in
            Text(s.formatText).foregroundStyle(.secondary)
        }
        .width(52)
        .customizationID("format")
        .defaultVisibility(.hidden)
        TableColumn("Rate", value: \.sampleRate) { s in
            Text(s.sampleRate > 0 ? String(format: "%g kHz", s.sampleRate / 1000) : "")
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .width(68)
        .customizationID("rate")
        .defaultVisibility(.hidden)
        TableColumn("Ch", value: \.channels) { s in
            Text(s.channels == 0 ? "" : s.channels == 1 ? "Mono" : s.channels == 2 ? "Stereo" : "\(s.channels) ch")
                .foregroundStyle(.secondary)
        }
        .width(52)
        .customizationID("channels")
        .defaultVisibility(.hidden)
        TableColumn("Size", value: \.size) { s in
            Text(s.size.formatted(.byteCount(style: .file))).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(68)
        .customizationID("size")
        .defaultVisibility(.hidden)
        TableColumn("Modified", value: \.mtime) { s in
            Text(Date(timeIntervalSince1970: s.mtime).formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(.secondary).lineLimit(1)
        }
        .width(min: 70, ideal: 96)
        .customizationID("modified")
        .defaultVisibility(.hidden)
    }
}

/// The name cell takes the click away from the table, so the table never becomes the focused view: the row stays
/// grey and the arrow keys keep moving the selection in whatever had focus before (the sidebar). Hand the table
/// the keyboard focus by finding it under the click.
@MainActor private func focusTableUnderClick() {
    guard let event = NSApp.currentEvent, let window = event.window ?? NSApp.keyWindow,
          let root = window.contentView else { return }
    var view = root.hitTest(root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
    while let current = view, !(current is NSTableView) { view = current.superview }
    if let table = view as? NSTableView, window.firstResponder !== table { window.makeFirstResponder(table) }
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
