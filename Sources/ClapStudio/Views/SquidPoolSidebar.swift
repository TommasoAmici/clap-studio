import ClapCore
import SwiftUI

/// The Pool of a stick in the sidebar: a row that opens to show its folders, and folders that open to show theirs.
struct PoolSidebarRows: View {
    @Environment(AppModel.self) private var model
    let drive: UsbDrive
    let stick: SquidStickContents
    /// Which rows are open, shared with the sets above (`key(drive:path:)`).
    @Binding var open: Set<String>

    /// The Pool itself has an empty path.
    static func key(drive: String, path: [String]) -> String { drive + "|pool|" + PoolOutline.key(path) }

    /// The folders that can be seen now, each with how far in it sits: a folder's contents show only while it is open.
    private var visibleFolders: [(folder: SquidPoolFolder, depth: Int)] {
        var shown: [(SquidPoolFolder, Int)] = []
        func walk(_ folders: [SquidPoolFolder], depth: Int) {
            for folder in folders {
                shown.append((folder, depth))
                if open.contains(Self.key(drive: drive.id, path: folder.path)) { walk(folder.children, depth: depth + 1) }
            }
        }
        if open.contains(Self.key(drive: drive.id, path: [])) { walk(stick.poolFolders, depth: 0) }
        return shown
    }

    var body: some View {
        HStack {
            disclosure(path: [], hasChildren: !stick.poolFolders.isEmpty)
            Label("Pool", systemImage: "tray.2")
            Spacer()
        }
        .tag(UsbSelection(drive: drive.id, area: .pool).tag)
        .help("Loose samples and folders the module can load into any channel")
        .contextMenu {
            Button("Send Samples Here…") { model.openSquidExport(ids: model.actionTargets, drive: drive.id, pool: true) }
            Divider()
            Button("Reveal in Finder") { reveal([]) }
        }
        ForEach(visibleFolders, id: \.folder.id) { entry in
            folderRow(entry.folder, depth: entry.depth)
        }
    }

    private func folderRow(_ folder: SquidPoolFolder, depth: Int) -> some View {
        HStack {
            disclosure(path: folder.path, hasChildren: !folder.children.isEmpty)
            Label(folder.name, systemImage: "folder").lineLimit(1)
            Spacer()
            Text("\(folder.totalSampleCount)").foregroundStyle(.secondary).monospacedDigit().font(.caption)
        }
        .padding(.leading, 18 * CGFloat(depth + 1))
        .tag(UsbSelection(drive: drive.id, area: .poolFolder(folder.path)).tag)
        .help(([SquidLayout.poolFolder] + folder.path).joined(separator: "/"))
        .contextMenu {
            Button("Send Samples Here…") {
                model.openSquidExport(ids: model.actionTargets, drive: drive.id, pool: true, poolFolder: folder.path.joined(separator: "/"))
            }
            Divider()
            Button("Reveal in Finder") { reveal(folder.path) }
            Divider()
            Button("Move to Trash", role: .destructive) { model.trashPoolEntries([PoolEntry(drive: drive.id, path: folder.path)]) }
        }
    }

    /// The arrow that shows or hides what is inside.
    @ViewBuilder
    private func disclosure(path: [String], hasChildren: Bool) -> some View {
        let key = Self.key(drive: drive.id, path: path)
        if hasChildren {
            Button {
                if open.contains(key) { open.remove(key) } else { open.insert(key) }
            } label: {
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open.contains(key) ? 90 : 0))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help(open.contains(key) ? "Hide folders" : "Show folders")
        } else {
            Color.clear.frame(width: 10, height: 10)
        }
    }

    private func reveal(_ path: [String]) {
        let pool = SquidStick.poolURL(volume: drive.url) ?? SquidStick.rootURL(volume: drive.url)
        NSWorkspace.shared.open(path.reduce(pool) { $0.appendingPathComponent($1, isDirectory: true) })
    }
}
