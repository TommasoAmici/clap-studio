import AppKit
import ClapCore

/// Rows under an expanded joined sample keep their own order and may refer to the same source more than once.
enum JoinedTableRow {
    case sample(Int)
    case part(JoinedPart)
}

extension LibraryListCoordinator {
    func joinedPart(at row: Int) -> JoinedPart? {
        guard let joinedRows, row >= 0, row < joinedRows.count, case .part(let part) = joinedRows[row] else { return nil }
        return part
    }

    func rebuildJoinedRows(_ visible: [SampleRecord]) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_JOINED_EXPAND"] == "1",
           !requestedJoinedSnapshot, let sample = visible.first(where: \.isJoined) {
            requestedJoinedSnapshot = true
            Task { [weak self] in self?.toggleJoined(sample) }
        }
        #endif
        guard !expandedJoined.isEmpty,
              visible.contains(where: { $0.isJoined && expandedJoined.contains($0.id) }) else {
            joinedRows = nil
            rowOfID = Dictionary(visible.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            return
        }
        var rows: [JoinedTableRow] = []
        var found: [Int64: Int] = [:]
        for (index, sample) in visible.enumerated() {
            if found[sample.id] == nil { found[sample.id] = rows.count }
            rows.append(.sample(index))
            guard sample.isJoined, expandedJoined.contains(sample.id) else { continue }
            for part in joinedParts[sample.id] ?? [] {
                if let id = part.sourceID, model.sampleByID[id] != nil, found[id] == nil { found[id] = rows.count }
                rows.append(.part(part))
            }
        }
        joinedRows = rows
        rowOfID = found
    }

    /// Reuse links until the library changes, and cancel work superseded by a newer request.
    func refreshExpandedJoinedParts(invalidate: Bool = false) {
        joinedRefreshTask?.cancel()
        joinedRefreshTask = nil
        joinedRefreshVersion &+= 1
        let version = joinedRefreshVersion
        if invalidate { joinedParts.removeAll() }
        guard !expandedJoined.isEmpty, let store = model.store else { return }
        let requests = expandedJoined.compactMap { id -> (Int64, URL)? in
            guard joinedParts[id] == nil, let sample = model.sampleByID[id] else { return nil }
            return (id, sample.url)
        }
        guard !requests.isEmpty else { return }
        let worker = Task.detached(priority: .userInitiated) { () -> [Int64: [JoinedPart]]? in
            var found: [Int64: [JoinedPart]] = [:]
            for (id, url) in requests {
                guard !Task.isCancelled else { return nil }
                found[id] = store.joinedParts(for: url)
            }
            return Task.isCancelled ? nil : found
        }
        joinedRefreshTask = Task { [weak self] in
            let parts = await withTaskCancellationHandler(operation: { await worker.value },
                                                           onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self, self.joinedRefreshVersion == version, let parts else { return }
            self.joinedParts.merge(parts) { _, new in new }
            self.joinedRefreshTask = nil
            self.refreshJoinedRows()
        }
    }

    func toggleJoined(_ sample: SampleRecord) {
        if expandedJoined.contains(sample.id) { keepSelectionWhenCollapsing(sample) }
        if expandedJoined.remove(sample.id) != nil { joinedParts.removeValue(forKey: sample.id) }
        else { expandedJoined.insert(sample.id) }
        refreshExpandedJoinedParts()
        refreshJoinedRows()
    }

    /// A selected child that is about to disappear yields selection to the remaining rows or its parent.
    private func keepSelectionWhenCollapsing(_ sample: SampleRecord) {
        guard let table, let joinedRows,
              let parent = joinedRows.firstIndex(where: { line in
                  if case .sample(let index) = line, model.visible.indices.contains(index) {
                      return model.visible[index].id == sample.id
                  }
                  return false
              }) else { return }
        var end = parent + 1
        while end < joinedRows.count {
            if case .sample = joinedRows[end] { break }
            end += 1
        }
        let disappearing = table.selectedRowIndexes.intersection(IndexSet(integersIn: (parent + 1)..<end))
        guard !disappearing.isEmpty else { return }
        let remaining = table.selectedRowIndexes.subtracting(disappearing).compactMap { self.sample(at: $0)?.id }
        let ids = remaining.isEmpty ? [sample.id] : remaining
        model.tableSelection = Set(ids)
        if model.selectedID.map({ !model.tableSelection.contains($0) }) ?? true {
            model.select(ids.last, keepSelection: true)
        }
    }

    private func refreshJoinedRows() {
        guard let table else { return }
        changingSelection = true
        rebuildRows()
        table.reloadData()
        changingSelection = false
        applySelection(model.tableSelection, in: table)
    }

    func joinedPartView(_ part: JoinedPart, in table: NSTableView) -> NSView {
        let id = NSUserInterfaceItemIdentifier("joinedPart")
        let cell = table.makeView(withIdentifier: id, owner: nil) as? JoinedPartCell ?? JoinedPartCell()
        cell.identifier = id
        let sample = part.sourceID.flatMap { model.sampleByID[$0] }
        cell.configure(part, sample: sample)
        return cell
    }
}

/// A source can be auditioned and selected while it is in the library; its original name remains when unavailable.
final class JoinedPartCell: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let unavailable = NSTextField(labelWithString: "Not in library")

    init() {
        super.init(frame: .zero)
        icon.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Source sample")
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        unavailable.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        unavailable.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [icon, label, unavailable])
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 25),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -3),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ part: JoinedPart, sample: SampleRecord?) {
        label.stringValue = sample?.name ?? part.name
        unavailable.isHidden = sample != nil
        label.textColor = sample == nil ? .secondaryLabelColor : .labelColor
        toolTip = sample?.url.path ?? part.sourceURL.path
    }
}
