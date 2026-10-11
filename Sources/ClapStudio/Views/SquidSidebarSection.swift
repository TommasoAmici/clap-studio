import ClapCore
import SwiftUI

/// "USB Drives" in the sidebar: each connected stick with its sets (open one to see its banks) and the Pool.
struct SquidSidebarSection: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []
    @State private var openSets: Set<String> = []        // sets whose banks are listed, by `key(of:in:)`

    var body: some View {
        Section("USB Drives") {
            ForEach(model.usbDrives) { drive in
                DisclosureGroup(isExpanded: Binding(get: { !collapsed.contains(drive.id) },
                                                    set: { if $0 { collapsed.remove(drive.id) } else { collapsed.insert(drive.id) } })) {
                    contents(of: drive)
                } label: {
                    Label(drive.name, systemImage: "externaldrive.fill.badge.checkmark")
                        .contextMenu {
                            Button("New Set") { model.newSet(on: drive.id) }
                                .disabled((model.usbContents[drive.id]?.namedSetCount ?? 0) >= SquidLayout.maxSets)
                            Button("Send Samples Here…") { model.openSquidExport(ids: model.actionTargets, drive: drive.id) }
                            Divider()
                            Button("Reveal in Finder") { NSWorkspace.shared.open(drive.url) }
                            Button("Eject") { model.ejectUsb(drive) }
                        }
                        .help(drive.url.path)
                }
            }
            .onAppear { reveal(model.usbSelection) }
            .onChange(of: model.usbSelection) { _, new in reveal(new) }
        }
    }

    @ViewBuilder
    private func contents(of drive: UsbDrive) -> some View {
        let stick = model.usbContents[drive.id] ?? SquidStickContents()
        if !drive.isFAT32 {
            Label("Formatted as \(drive.formatDescription.isEmpty ? "unknown" : drive.formatDescription). The module reads FAT32.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
        let sets = stick.sets.filter { $0.name == nil ? (!$0.banks.isEmpty || stick.namedSetCount == 0) : true }
        ForEach(sets) { set in
            row(for: set, drive: drive, stick: stick)
            if openSets.contains(key(of: set, in: drive)) {
                ForEach(set.banks) { bankRow($0, drive: drive) }
            }
        }
        if stick.hasPool {
            Label("Pool", systemImage: "tray.2").tag(UsbSelection(drive: drive.id, area: .pool).tag)
        }
    }

    private func row(for set: SquidSet, drive: UsbDrive, stick: SquidStickContents) -> some View {
        HStack {
            disclosure(for: set, in: drive)
            if let name = set.name, model.renamingUsb == .set(drive: drive.id, name: name) {
                Image(systemName: "square.stack.3d.up")
                SquidRenameField(initial: name, placeholder: "Set name",
                                 report: { SquidLayout.check(setName: $0, existing: stick.sets.compactMap(\.name), renaming: name) },
                                 commit: { model.renameSet(drive: drive.id, from: name, to: $0) },
                                 cancel: { model.renamingUsb = nil })
            } else {
                Label(set.title, systemImage: "square.stack.3d.up")
                if let name = set.name { NameIssueIcon(report: SquidLayout.check(setName: name)) }
                Spacer()
                Text("\(set.banks.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
            }
        }
        .tag(UsbSelection(drive: drive.id, area: .set(set.name)).tag)
        .help(set.name == nil ? "Banks in the ALM022 folder" : "Set \(set.title)")
        .contextMenu {
            Button("Send Samples Here…") { model.openSquidExport(ids: model.actionTargets, drive: drive.id, set: set.name) }
            Button("New Bank") { model.newBank(drive: drive.id, set: set.name) }
                .disabled(stick.freeBankNumbers(inSet: set.name).isEmpty)
            Divider()
            if let name = set.name {
                Button("Rename") { model.renamingUsb = .set(drive: drive.id, name: name) }
                Button("Reveal in Finder") { reveal(set: name, on: drive) }
                Divider()
                Button("Move to Trash", role: .destructive) { model.trashSet(drive: drive.id, name: name) }
            } else {
                Button("Reveal in Finder") { NSWorkspace.shared.open(SquidStick.rootURL(volume: drive.url)) }
            }
        }
    }

    private func key(of set: SquidSet, in drive: UsbDrive) -> String { drive.id + "|" + (set.name ?? "") }

    /// The arrow that shows or hides a set's banks.
    @ViewBuilder
    private func disclosure(for set: SquidSet, in drive: UsbDrive) -> some View {
        let key = key(of: set, in: drive)
        if set.banks.isEmpty {
            Color.clear.frame(width: 10, height: 10)
        } else {
            Button {
                if openSets.contains(key) { openSets.remove(key) } else { openSets.insert(key) }
            } label: {
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(openSets.contains(key) ? 90 : 0))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help(openSets.contains(key) ? "Hide banks" : "Show banks")
        }
    }

    /// A bank that is picked (here, or by making a new one) shows its set open.
    private func reveal(_ selection: UsbSelection?) {
        guard let selection, case .bank(let set, _) = selection.area else { return }
        openSets.insert(selection.drive + "|" + (set ?? ""))
    }

    private func bankRow(_ bank: SquidBank, drive: UsbDrive) -> some View {
        let report = SquidLayout.check(bankName: bank.name)
        return HStack {
            Label(bank.name.isEmpty ? "Bank \(bank.number)" : "\(bank.number) · \(bank.name)", systemImage: "square.grid.2x2")
                .lineLimit(1)
            if !report.isClean { NameIssueIcon(report: report) }
            Spacer()
            if bank.freeSlots > 0 {
                Text("\(bank.freeSlots)").font(.caption2.bold()).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .background(Color.orange, in: Capsule())
                    .help(bank.freeSlots == 1 ? "Room for 1 more sample" : "Room for \(bank.freeSlots) more samples")
            }
        }
        .padding(.leading, 18)
        .tag(UsbSelection(drive: drive.id, area: .bank(set: bank.set, number: bank.number)).tag)
        .contextMenu {
            Button("Rename") {
                model.selectSidebar(UsbSelection(drive: drive.id, area: .bank(set: bank.set, number: bank.number)).tag)
                model.renamingUsb = .bank(drive: drive.id, set: bank.set, number: bank.number)
            }
            if bank.freeSlots > 0 {
                Button("Add Samples…") {
                    model.openSquidExport(ids: model.actionTargets, drive: drive.id, set: bank.set, bank: bank.number)
                }
            }
            Button("Duplicate") { model.duplicateBank(drive: drive.id, set: bank.set, number: bank.number) }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.open(SquidStick.bankURL(set: bank.set, number: bank.number, volume: drive.url)
                                        ?? SquidStick.rootURL(volume: drive.url))
            }
            Divider()
            Button("Move to Trash", role: .destructive) { model.trashBank(drive: drive.id, set: bank.set, number: bank.number) }
        }
    }

    private func reveal(set name: String, on drive: UsbDrive) {
        NSWorkspace.shared.open(SquidStick.setURL(named: name, volume: drive.url) ?? SquidStick.rootURL(volume: drive.url))
    }
}
