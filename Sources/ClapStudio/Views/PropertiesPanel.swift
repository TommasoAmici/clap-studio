import ClapCore
import SwiftUI

/// Measured properties of the selected sample, with an editable tempo.
struct PropertiesPanel: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var bpmText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Properties").font(.subheadline.bold())
            if sample.loudnessDB == nil {
                Text(model.isIndexing ? "Measuring…" : "Not measured yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    row("Type", sample.typeText)
                    categoryRow
                    if !sample.moods.isEmpty { row("Mood", sample.moodText) }
                    if sample.isLoop == true { tempoRow }
                    row(sample.isLoop == true ? "Key" : "Note", sample.keyName ?? "–")
                    row("Level", sample.levelText)
                    row("Peak", sample.peakDB.map { String(format: "%.1f dB", $0) } ?? "")
                    row("Crest", sample.crestDB.map { String(format: "%.1f dB", $0) } ?? "")
                    row("Brightness", sample.brightnessText)
                }
                .font(.caption)
            }
            TagEditor(sample: sample).padding(.top, 8)
        }
        .onAppear(perform: syncText)
        .onChange(of: sample.id) { syncText() }
        .onChange(of: sample.bpmManual) { syncText() }
    }

    private var tempoRow: some View {
        GridRow {
            Text("Tempo").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("BPM", text: $bpmText)
                    .textFieldStyle(.roundedBorder).frame(width: 64).monospacedDigit()
                    .onSubmit(commit)
                if sample.bpmManual != nil {
                    Button("Use detected") { model.setBPM(sample.id, nil) }.controlSize(.mini)
                        .help("Detected: \(sample.bpm.map { String(format: "%.1f", $0) } ?? "none")")
                } else {
                    Text("detected").foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var categoryRow: some View {
        GridRow {
            Text("Category").foregroundStyle(.secondary)
            Menu {
                ForEach(SoundCategories.names, id: \.self) { name in
                    Button(name) { model.setCategory(sample.id, name) }
                }
                if sample.categoryManual != nil {
                    Divider()
                    Button("Use automatic" + (sample.category.map { " (\($0))" } ?? "")) { model.setCategory(sample.id, nil) }
                }
            } label: {
                Text((sample.effectiveCategory ?? "None") + (sample.categoryManual != nil ? " ✎" : ""))
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value.isEmpty ? "–" : value).monospacedDigit()
        }
    }

    private func syncText() {
        bpmText = sample.effectiveBPM.map { String(format: $0.rounded() == $0 ? "%.0f" : "%.1f", $0) } ?? ""
    }

    private func commit() {
        if let value = Double(bpmText.replacingOccurrences(of: ",", with: ".")), (20...400).contains(value) {
            model.setBPM(sample.id, value)
        } else {
            syncText()
        }
    }
}

/// The sample's tags as removable chips, with a field to add more.
struct TagEditor: View {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.subheadline.bold())
            if !sample.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(sample.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag).font(.caption)
                            Button { model.removeTag(tag, from: [sample.id]) } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }
            TextField("Add a tag", text: $newTag)
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .onSubmit { model.addTag(newTag, to: [sample.id]); newTag = "" }
        }
    }
}

/// Lays chips out in rows, wrapping to the next line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 300, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(bounds.width, subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
