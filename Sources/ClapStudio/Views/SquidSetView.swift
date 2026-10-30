import ClapCore
import SwiftUI

/// The banks of one set on a stick, with their eight samples each. Click a sample to hear it; drag it into a DAW.
struct SquidSetView: View {
    @Environment(AppModel.self) private var model
    let selection: UsbSelection
    let setName: String?
    /// Shows just this bank (picked in the sidebar) rather than every bank of the set.
    var onlyBank: Int?

    var body: some View {
        let drive = model.drive(id: selection.drive)
        let set = model.usbContents[selection.drive]?.set(named: setName)
        let slots = slotMap()
        let banks = (set?.banks ?? []).filter { onlyBank == nil || $0.number == onlyBank }
        VStack(spacing: 0) {
            HStack {
                Label(set?.title ?? "Set", systemImage: "square.stack.3d.up").font(.headline)
                if let onlyBank {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    Text("Bank \(onlyBank)").font(.headline)
                }
                Text("on \(drive?.name ?? "USB drive")").foregroundStyle(.secondary)
                Spacer()
                Button("New Bank") { model.newBank(drive: selection.drive, set: setName) }
                    .disabled(model.usbContents[selection.drive]?.freeBankNumbers(inSet: setName).isEmpty ?? true)
                    .help("Make an empty bank in this set")
                Button("Send Samples…") { model.openSquidExport(ids: model.actionTargets, drive: selection.drive, set: setName, bank: onlyBank) }
                    .help(onlyBank == nil ? "Add a bank to this set" : "Add samples to this bank")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if !banks.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(banks) { bank in
                            BankCard(bank: bank, samples: slots[bank.number] ?? [:], drive: drive,
                                     otherSets: (model.usbContents[selection.drive]?.sets ?? []).filter { !SquidLayout.sameSet($0.name, bank.set) }.map(\.name))
                        }
                    }
                    .padding(14)
                }
            } else {
                ContentUnavailableView {
                    Label("No banks yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Send samples from the library or the drum machine to make the first bank, or make an empty one.")
                } actions: {
                    Button("New Bank") { model.newBank(drive: selection.drive, set: setName) }
                }
                .frame(maxHeight: .infinity)        // fills the rest, so the header stays at the top
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
    let otherSets: [String?]        // where "Move to" can send the bank

    private var renameState: UsbRename? { drive.map { .bank(drive: $0.id, set: bank.set, number: bank.number) } }
    private var nameReport: SquidNameReport { SquidLayout.check(bankName: bank.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bank \(bank.number)").font(.subheadline.bold())
                    .onTapGesture(count: 2) { model.renamingUsb = renameState }
                if let drive, model.renamingUsb == renameState {
                    SquidRenameField(initial: bank.name, placeholder: "Bank name", report: { SquidLayout.check(bankName: $0) },
                                     commit: { model.renameBank(drive: drive.id, set: bank.set, number: bank.number, to: $0) },
                                     cancel: { model.renamingUsb = nil })
                        .frame(maxWidth: 240)
                } else if !bank.name.isEmpty {
                    Text(bank.name).font(.subheadline.monospaced()).foregroundStyle(nameReport.isClean ? Color.secondary : Color.orange)
                    NameIssueIcon(report: nameReport)
                }
                if bank.freeSlots > 0 { FreeSlotsBadge(count: bank.freeSlots, horizontalPadding: 6) }
                Spacer()
                Button("Try in Drum Machine") { model.loadBankIntoDrums((1...SquidLayout.slotsPerBank).compactMap { samples[$0] }) }
                    .disabled(samples.isEmpty).controlSize(.small)
                Button { reveal() } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Reveal in Finder")
            }
            HStack(spacing: 6) {
                ForEach(1...SquidLayout.slotsPerBank, id: \.self) { slot in cell(slot) }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu { bankMenu }
    }

    @ViewBuilder
    private var bankMenu: some View {
        if let drive {
            Button("Rename") { model.renamingUsb = renameState }
            if bank.freeSlots > 0 {
                Button("Add Samples…") {
                    model.openSquidExport(ids: model.actionTargets, drive: drive.id, set: bank.set, bank: bank.number)
                }
            }
            Button("Duplicate") { model.duplicateBank(drive: drive.id, set: bank.set, number: bank.number) }
            if !otherSets.isEmpty {
                Menu("Move to") {
                    ForEach(otherSets, id: \.self) { target in
                        Button(target.map { "Set \($0)" } ?? "Default set") {
                            model.moveBank(drive: drive.id, set: bank.set, number: bank.number, to: target)
                        }
                    }
                }
            }
            Divider()
            Button("Reveal in Finder") { reveal() }
            Divider()
            Button("Move to Trash", role: .destructive) { model.trashBank(drive: drive.id, set: bank.set, number: bank.number) }
        }
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
        .contextMenu {
            if sample != nil, let drive {
                Button("Move Sample to Trash", role: .destructive) {
                    model.trashUsbSample(drive: drive.id, set: bank.set, number: bank.number, slot: slot)
                }
            }
        }
    }

    private func reveal() {
        guard let drive else { return }
        let folder = SquidStick.bankURL(set: bank.set, number: bank.number, volume: drive.url)
            ?? SquidStick.rootURL(volume: drive.url).appendingPathComponent(bank.folder, isDirectory: true)
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
