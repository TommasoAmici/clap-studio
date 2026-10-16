import ClapCore
import SwiftUI

/// The sound edits (reverse, speed, volume, filters) for several samples at once. A part the samples agree on shows
/// its value; one they differ on shows "Mixed" and is left alone until it is changed here, which sets it for all.
struct MultiEditPanel: View {
    @Environment(AppModel.self) private var model
    let samples: [SampleRecord]
    @State private var open = false
    /// The slider position of a part being dragged, until the mouse is let go.
    @State private var pending: [Part: Double] = [:]

    private enum Part { case speed, volume, lowPass, highPass }
    private enum Shared<T: Equatable>: Equatable { case same(T), mixed }

    private var ids: [Int64] { samples.filter { $0.duration > 0 }.map(\.id) }
    private var edits: [SampleEdit] { samples.filter { $0.duration > 0 }.map(model.edit(for:)) }

    private func shared<T: Equatable>(_ value: (SampleEdit) -> T) -> Shared<T> {
        let all = edits
        guard let first = all.first.map(value) else { return .mixed }
        return all.allSatisfy { value($0) == first } ? .same(first) : .mixed
    }

    var body: some View {
        let anyEdited = edits.contains { !$0.isNeutral }
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                reverseRow
                slider("Speed", .speed, range: SampleEdit.speedRange, current: shared(\.speedSemitones),
                       format: { String(format: "%+.1f st", $0) }) { $0.speedSemitones = $1 }
                slider("Volume", .volume, range: SampleEdit.gainRange, current: shared(\.gainDB),
                       format: { String(format: "%+.1f dB", $0) }) { $0.gainDB = $1 }
                filter("Low-pass", .lowPass, current: shared(\.lowPassHz)) { $0.lowPassHz = $1 }
                filter("High-pass", .highPass, current: shared(\.highPassHz)) { $0.highPassHz = $1 }
                HStack {
                    Spacer()
                    if anyEdited { Button("Reset") { model.changeEdits(ids) { $0 = SampleEdit() } } }
                }
                .controlSize(.small)
                Text("Applies to every selected sample. Files are not changed; each keeps its own trim.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            Text("Edit sound").font(.subheadline.bold())
                .foregroundStyle(anyEdited ? Color.accentColor : Color.primary)
        }
        .disabled(ids.isEmpty)
    }

    // MARK: rows

    /// A checkbox that can also be "some of them".
    private var reverseRow: some View {
        let state = shared(\.reverse)
        let symbol = state == .same(true) ? "checkmark.square.fill" : state == .same(false) ? "square" : "minus.square.fill"
        return Button {
            let turnOn = state != .same(true)
            model.changeEdits(ids) { $0.reverse = turnOn }
        } label: {
            Label("Reverse", systemImage: symbol)
        }
        .buttonStyle(.borderless)
    }

    private func slider(_ title: String, _ part: Part, range: ClosedRange<Double>, current: Shared<Double>,
                        format: @escaping (Double) -> String, apply: @escaping (inout SampleEdit, Double) -> Void) -> some View {
        let shown: Double? = pending[part] ?? { if case .same(let value) = current { return value } else { return nil } }()
        return HStack {
            Text(title).font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { shown ?? 0 }, set: { pending[part] = $0 }), in: range, onEditingChanged: { editing in
                guard !editing, let value = pending[part] else { return }
                pending[part] = nil
                model.changeEdits(ids) { apply(&$0, value) }
            })
            Text(label(shown, format: format)).font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
        }
    }

    /// A frequency on a logarithmic scale, with the far end meaning off.
    private func filter(_ title: String, _ part: Part, current: Shared<Double?>,
                        apply: @escaping (inout SampleEdit, Double?) -> Void) -> some View {
        let isLowPass = part == .lowPass
        let range = SampleEdit.filterRange
        func hertz(at position: Double) -> Double? {
            let off = isLowPass ? position >= 0.99 : position <= 0.01
            return off ? nil : range.lowerBound * pow(range.upperBound / range.lowerBound, position)
        }
        func position(of hz: Double?) -> Double {
            hz.map { log(max($0, range.lowerBound) / range.lowerBound) / log(range.upperBound / range.lowerBound) } ?? (isLowPass ? 1 : 0)
        }
        let known: Double?? = { if case .same(let value) = current { return .some(value) } else { return nil } }()
        let shown: Double? = pending[part] ?? known.map(position(of:))
        let text: String = {
            if let dragged = pending[part] { return hertz(at: dragged).map(SampleEdit.hertz) ?? "off" }
            guard let known else { return "Mixed" }
            return known.map(SampleEdit.hertz) ?? "off"
        }()
        return HStack {
            Text(title).font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { shown ?? (isLowPass ? 1 : 0) }, set: { pending[part] = $0 }), in: 0...1, onEditingChanged: { editing in
                guard !editing, let dragged = pending[part] else { return }
                pending[part] = nil
                let hz = hertz(at: dragged)
                model.changeEdits(ids) { apply(&$0, hz) }
            })
            Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
        }
    }

    private func label(_ value: Double?, format: (Double) -> String) -> String {
        guard let value else { return "Mixed" }
        return abs(value) < 0.05 ? "off" : format(value)
    }
}
