import ClapCore
import SwiftUI

/// "USB Drives" in the sidebar: each connected stick with the sets and the Pool on it.
struct SquidSidebarSection: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []

    var body: some View {
        Section("USB Drives") {
            if model.usbDrives.isEmpty {
                Text("No USB drive connected").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.usbDrives) { drive in
                DisclosureGroup(isExpanded: Binding(get: { !collapsed.contains(drive.id) },
                                                    set: { if $0 { collapsed.remove(drive.id) } else { collapsed.insert(drive.id) } })) {
                    contents(of: drive)
                } label: {
                    Label(drive.name, systemImage: "externaldrive.fill.badge.checkmark")
                        .contextMenu {
                            Button("Send Samples Here…") { model.openSquidExport(ids: model.actionTargets, drive: drive.id) }
                            Button("Reveal in Finder") { NSWorkspace.shared.open(drive.url) }
                            Divider()
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
        if stick.hasSquidFolder {
            ForEach(stick.sets.filter { $0.name == nil ? (!$0.banks.isEmpty || stick.namedSetCount == 0) : true }) { set in
                HStack {
                    Label(set.title, systemImage: "square.stack.3d.up")
                    Spacer()
                    Text("\(set.banks.count)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
                }
                .tag(UsbSelection(drive: drive.id, area: .set(set.name)).tag)
                .help(set.name == nil ? "Banks in the ALM022 folder" : "Set \(set.title)")
            }
            if stick.hasPool {
                Label("Pool", systemImage: "tray.2").tag(UsbSelection(drive: drive.id, area: .pool).tag)
            }
        } else {
            Text("No ALM022 folder yet").font(.caption).foregroundStyle(.secondary)
        }
    }
}
