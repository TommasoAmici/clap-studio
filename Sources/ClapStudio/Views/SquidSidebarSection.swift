import ClapCore
import SwiftUI

/// "USB Drives" in the sidebar: each connected stick with the sets and the Pool on it.
struct SquidSidebarSection: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []

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
        ForEach(stick.sets.filter { $0.name == nil ? (!$0.banks.isEmpty || stick.namedSetCount == 0) : true }) { set in
            row(for: set, drive: drive, stick: stick)
        }
        if stick.hasPool {
            Label("Pool", systemImage: "tray.2").tag(UsbSelection(drive: drive.id, area: .pool).tag)
        }
    }

    private func row(for set: SquidSet, drive: UsbDrive, stick: SquidStickContents) -> some View {
        HStack {
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

    private func reveal(set name: String, on drive: UsbDrive) {
        NSWorkspace.shared.open(SquidStick.setURL(named: name, volume: drive.url) ?? SquidStick.rootURL(volume: drive.url))
    }
}
