import AppKit
import ClapCore

/// In the Pool of a stick the list has folder headings between the samples. These helpers tell which line is which, so the
/// rest of the table never has to know: a line is a sample (an index into `model.visible`) or a folder.
extension LibraryListCoordinator {
    /// The sample on a line, nil for a folder heading or a line past the end.
    func sample(at row: Int) -> SampleRecord? {
        guard row >= 0 else { return nil }
        guard let groupedRows else { return row < model.visible.count ? model.visible[row] : nil }
        guard row < groupedRows.count, case .sample(let index) = groupedRows[row], index < model.visible.count else { return nil }
        return model.visible[index]
    }

    /// The folder a heading stands for, with how far in it sits and whether it is open.
    func folder(at row: Int) -> (folder: SquidPoolFolder, depth: Int, expanded: Bool)? {
        guard let groupedRows, row >= 0, row < groupedRows.count, case .folder(let folder, let depth, let expanded) = groupedRows[row] else { return nil }
        return (folder, depth, expanded)
    }

    /// Lays the samples out again, under their folders in the Pool and in one list anywhere else.
    func rebuildRows() {
        let visible = model.visible
        guard let pool else {
            groupedRows = nil
            rowOfID = Dictionary(visible.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            return
        }
        let items = visible.enumerated().map { index, sample -> (folder: [String], item: Int) in
            if case .pool(let folders) = SquidLayout.location(ofRelativePath: sample.relPath) { return (folders, index) }
            return ([], index)
        }
        let rows = PoolOutline.rows(root: pool.root, folders: pool.folders, items: items, collapsed: pool.closed)
        groupedRows = rows
        var found: [Int64: Int] = [:]
        for (row, line) in rows.enumerated() {
            if case .sample(let index) = line, found[visible[index].id] == nil { found[visible[index].id] = row }
        }
        rowOfID = found
    }

    func folderView(_ line: (folder: SquidPoolFolder, depth: Int, expanded: Bool), in table: NSTableView) -> NSView {
        let id = NSUserInterfaceItemIdentifier("poolFolder")
        let cell = table.makeView(withIdentifier: id, owner: nil) as? PoolFolderCell ?? PoolFolderCell()
        cell.identifier = id
        cell.configure(line.folder, depth: line.depth, expanded: line.expanded)
        cell.onToggle = { [weak self] in
            guard let self, let pool = self.pool else { return }
            self.model.togglePoolFolder(drive: pool.drive, path: line.folder.path)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { folder(at: row) != nil }

    /// Headings open and close; they are never part of a selection.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { folder(at: row) == nil }
}

/// A folder heading: an arrow, the folder's name and how many samples it holds. A click anywhere on it opens or closes it.
final class PoolFolderCell: NSTableCellView {
    private let arrow = NSImageView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private var indent: NSLayoutConstraint?
    var onToggle: (() -> Void)?

    init() {
        super.init(frame: .zero)
        arrow.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        arrow.contentTintColor = .secondaryLabelColor
        icon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        count.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [arrow, icon, label, count])
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3)
        indent = leading
        NSLayoutConstraint.activate([
            leading,
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -3),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 10),
        ])
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ folder: SquidPoolFolder, depth: Int, expanded: Bool) {
        label.stringValue = folder.name
        count.stringValue = "\(folder.totalSampleCount)"
        arrow.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                              accessibilityDescription: expanded ? "Open" : "Closed")
        indent?.constant = 3 + 16 * CGFloat(depth)
        toolTip = (["Pool"] + folder.path).joined(separator: "/")
    }

    override func mouseDown(with event: NSEvent) { onToggle?() }
}
