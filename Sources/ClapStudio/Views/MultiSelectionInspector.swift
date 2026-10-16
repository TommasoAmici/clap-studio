import ClapCore
import SwiftUI

/// The inspector while several samples are highlighted: what they share is shown as it is, what differs as
/// "Mixed", and anything set here is applied to all of them.
struct MultiSelectionInspector: View {
    @Environment(AppModel.self) private var model
    let samples: [SampleRecord]
    @State private var bpmText = ""
    @State private var newTag = ""

    private var ids: [Int64] { samples.map(\.id) }
    private var loops: [SampleRecord] { samples.filter { $0.isLoop == true } }
    private static let mixed = "Mixed"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 6) {
                Text("Properties").font(.subheadline.bold())
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    row("Type", shared(\.typeText))
                    categoryRow
                    moodRow
                    if !loops.isEmpty { tempoRow }
                    row("Key", shared { $0.keyName ?? "" })
                    row("Format", shared(\.formatText))
                }
                .font(.caption)
            }
            tags
        }
        .onAppear(perform: syncText)
        .onChange(of: tempoKey) { syncText() }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(samples.count) samples selected").font(.headline)
            Text("Changes here apply to all of them.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(Format.duration(samples.reduce(0) { $0 + $1.duration }) + " in total")
                Spacer()
                let allFavorite = samples.allSatisfy(\.favorite)
                Button { model.toggleFavorite(ids) } label: { Image(systemName: allFavorite ? "star.fill" : "star") }
                    .buttonStyle(.borderless).foregroundStyle(allFavorite ? .yellow : .secondary)
                    .help(allFavorite ? "Remove from favorites (F)" : "Add to favorites (F)")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: shared values

    /// The value every selected sample has, or nil when they differ.
    private func shared<T: Equatable>(_ value: (SampleRecord) -> T) -> T? {
        guard let first = samples.first.map(value) else { return nil }
        return samples.allSatisfy { value($0) == first } ? first : nil
    }

    private func row(_ title: String, _ value: String?) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value.map { $0.isEmpty ? "–" : $0 } ?? Self.mixed)
                .foregroundStyle(value == nil ? Color.secondary : Color.primary).monospacedDigit()
        }
    }

    // MARK: category and mood

    private var categoryRow: some View {
        GridRow {
            Text("Category").foregroundStyle(.secondary)
            Menu {
                ForEach(SoundCategories.names, id: \.self) { name in
                    Button(name) { model.setCategory(ids, name) }
                }
                if samples.contains(where: { $0.categoryManual != nil }) {
                    Divider()
                    Button("Use automatic") { model.setCategory(ids, nil) }
                }
            } label: {
                Text((shared { $0.effectiveCategory ?? "None" } ?? Self.mixed)
                     + (samples.contains { $0.categoryManual != nil } ? " ✎" : ""))
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    /// A mood is on for all, some or none of the samples; picking it turns it on for all, or off if it already is.
    private var moodRow: some View {
        GridRow {
            Text("Mood").foregroundStyle(.secondary)
            Menu {
                ForEach(SoundMoods.names, id: \.self) { name in
                    let count = samples.filter { $0.moods.contains(name) }.count
                    let onForAll = count == samples.count
                    Button {
                        model.changeMoods(ids, named: onForAll ? "Remove Mood \(name)" : "Add Mood \(name)") { moods in
                            onForAll ? moods.filter { $0 != name } : (moods.contains(name) ? moods : moods + [name])
                        }
                    } label: {
                        if count == 0 { Text(name) }
                        else { Label(name, systemImage: onForAll ? "checkmark" : "minus") }
                    }
                }
                if samples.contains(where: { $0.moodsManual != nil }) {
                    Divider()
                    Button("Use automatic") { model.changeMoods(ids, named: "Use Automatic Moods") { _ in nil } }
                }
            } label: {
                Text(moodSummary + (samples.contains { $0.moodsManual != nil } ? " ✎" : ""))
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private var moodSummary: String {
        guard let moods = shared(\.moods) else { return Self.mixed }
        return moods.isEmpty ? "None" : moods.joined(separator: ", ")
    }

    // MARK: tempo

    /// Changes whenever a loop's tempo does, so the field follows undo and edits made elsewhere.
    private var tempoKey: [Double] { [Double(loops.count)] + loops.map { $0.effectiveBPM ?? -1 } }

    private var tempoRow: some View {
        GridRow {
            Text("Tempo").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TextField("BPM", text: $bpmText, prompt: Text(Self.mixed))
                        .textFieldStyle(.roundedBorder).frame(width: 64).monospacedDigit()
                        .onSubmit(commitTempo)
                    if loops.contains(where: { $0.bpmManual != nil }) {
                        Button("Use detected") { model.setBPM(loops.map(\.id), nil) }.controlSize(.mini)
                            .help("Go back to the tempo found in each file")
                    }
                }
                if loops.count != samples.count {
                    Text("Applies to the \(loops.count) loop\(loops.count == 1 ? "" : "s") only")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func syncText() {
        bpmText = shared(\.effectiveBPM, among: loops).map(Format.bpm) ?? ""
    }

    /// The tempo every one of `group` has, or nil when they differ or none is known.
    private func shared(_ value: (SampleRecord) -> Double?, among group: [SampleRecord]) -> Double? {
        guard let first = group.first.flatMap(value), group.allSatisfy({ value($0) == first }) else { return nil }
        return first
    }

    private func commitTempo() {
        let text = bpmText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if let value = Double(text), (20...400).contains(value) {
            model.setBPM(loops.map(\.id), value)
        }
        syncText()
    }

    // MARK: tags

    /// Every tag on any of the samples, with how many have it.
    private var tagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for sample in samples { for tag in sample.tags { counts[tag, default: 0] += 1 } }
        return counts.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
    }

    private struct TagCount: Identifiable {
        let tag: String
        let count: Int
        var id: String { tag }
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.subheadline.bold())
            FlowLayout(spacing: 6) {
                ForEach(tagCounts) { entry in chip(entry.tag, count: entry.count) }
            }
            TextField("Add a tag to all", text: $newTag)
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .onSubmit { model.addTag(newTag, to: ids); newTag = "" }
            if tagCounts.contains(where: { $0.count < samples.count }) {
                Text("Faded tags are on some of the samples only. Picking x removes them from those.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func chip(_ tag: String, count: Int) -> some View {
        let onAll = count == samples.count
        return HStack(spacing: 4) {
            Text(onAll ? tag : "\(tag) (\(count))").font(.caption)
            Button { model.removeTag(tag, from: ids) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .opacity(onAll ? 1 : 0.6)
    }
}
