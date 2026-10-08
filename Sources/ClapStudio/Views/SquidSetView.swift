import ClapCore
import SwiftUI

/// The banks of one set on a stick, with their eight samples each. Click a sample to hear it; drag it into a DAW.
struct SquidSetView: View {
    @Environment(AppModel.self) private var model
    let selection: UsbSelection
    let setName: String?

    var body: some View {
        let drive = model.drive(id: selection.drive)
        let set = model.usbContents[selection.drive]?.set(named: setName)
        let slots = slotMap()
        VStack(spacing: 0) {
            HStack {
                Label(set?.title ?? "Set", systemImage: "square.stack.3d.up").font(.headline)
                Text("on \(drive?.name ?? "USB drive")").foregroundStyle(.secondary)
                Spacer()
                Button("Send Samples…") { model.openSquidExport(ids: model.actionTargets, drive: selection.drive, set: setName) }
                    .help("Add a bank to this set")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if let set, !set.banks.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(set.banks) { bank in BankCard(bank: bank, samples: slots[bank.number] ?? [:], drive: drive) }
                    }
                    .padding(14)
                }
            } else {
                ContentUnavailableView("No banks yet", systemImage: "square.stack.3d.up",
                                       description: Text("Send samples from the library or the drum machine to make the first bank."))
            }
        }
    }

    /// Bank number to channel to sample.
    private func slotMap() -> [Int: [Int: SampleRecord]] {
        var map: [Int: [Int: SampleRecord]] = [:]
        for sample in model.usbSamples(in: selection) {
            if case .bank(_, let number, let slot?) = SquidLayout.location(ofRelativePath: sample.relPath) {
                map[number, default: [:]][slot] = map[number]?[slot] ?? sample
            }
        }
        return map
    }
}

private struct BankCard: View {
    @Environment(AppModel.self) private var model
    let bank: SquidBank
    let samples: [Int: SampleRecord]
    let drive: UsbDrive?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bank \(bank.number)").font(.subheadline.bold())
                if !bank.name.isEmpty { Text(bank.name).font(.subheadline.monospaced()).foregroundStyle(.secondary) }
                Spacer()
                Button("Try in Drum Machine") { model.loadBankIntoDrums((1...SquidLayout.slotsPerBank).compactMap { samples[$0] }) }
                    .disabled(samples.isEmpty).controlSize(.small)
                Button { reveal() } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Show in Finder")
            }
            HStack(spacing: 6) {
                ForEach(1...SquidLayout.slotsPerBank, id: \.self) { slot in cell(slot) }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func cell(_ slot: Int) -> some View {
        let sample = samples[slot]
        let selected = sample != nil && model.selectedID == sample?.id
        VStack(alignment: .leading, spacing: 2) {
            Text("\(slot)").font(.caption2.bold()).foregroundStyle(.secondary)
            Text(sample?.name ?? "empty").font(.caption).lineLimit(2)
                .foregroundStyle(sample == nil ? .tertiary : .primary)
            if let sample { Text(String(format: "%.1f s", sample.duration)).font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { if let sample { model.select(sample.id, play: true) } }
        .modifier(OptionalSampleDrag(sample: sample))
    }

    private func reveal() {
        guard let drive else { return }
        let folder = SquidStick.rootURL(volume: drive.url).appendingPathComponent(bank.folder, isDirectory: true)
        NSWorkspace.shared.open(folder)
    }
}

private struct OptionalSampleDrag: ViewModifier {
    @Environment(AppModel.self) private var model
    let sample: SampleRecord?

    func body(content: Content) -> some View {
        if let sample { content.sampleDrag(sample, model: model) } else { content }
    }
}
