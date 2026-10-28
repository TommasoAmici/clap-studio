import AppKit
import ClapCore
import SwiftUI

/// The library list as a plain AppKit table. SwiftUI's `Table` rebuilds its whole row graph whenever the rows
/// change (about 100 µs per row), which froze the app for seconds with tens of thousands of samples. An
/// `NSTableView` only ever makes views for the rows on screen, so changing the filter costs the same however
/// large the library is.
struct LibraryList: NSViewRepresentable {
    let model: AppModel
    /// Inputs the list draws from. SwiftUI re-runs `updateNSView` when any of them change.
    let revision: Int
    let joinedLinksRevision: Int
    let selection: Set<Int64>
    let sortOrder: [KeyPathComparator<SampleRecord>]
    let drumTracks: [Int64: Int]
    let segmentMatches: [Int64: SegmentMatch]
    let shuffleSeed: UInt64?
    /// Set in the Pool of a stick, where folders show as headings that open and close.
    let pool: PoolLayout?

    func makeCoordinator() -> LibraryListCoordinator { LibraryListCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        let table = context.coordinator.makeTable()
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(revision: revision, joinedLinksRevision: joinedLinksRevision,
                                   selection: selection, sortOrder: sortOrder,
                                   shuffleSeed: shuffleSeed, pool: pool)
    }
}

/// A table that forwards the keys the app binds (they are handled at the window level elsewhere) and replays a
/// sample when its already-selected row is clicked again.
final class LibraryNSTableView: NSTableView {
    var menuForRows: (([Int]) -> NSMenu?)?
    var onKey: ((NSEvent) -> Bool)?
    var onReclick: ((Int) -> Void)?

    /// Where a shift-arrow selection started (`anchorRow`) and the end that moves (`cursorRow`), as in Finder.
    private var anchorRow = -1
    private var cursorRow = -1

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .shift, event.keyCode == 125 || event.keyCode == 126 {
            extendSelection(by: event.keyCode == 125 ? 1 : -1)
            return
        }
        super.keyDown(with: event)
    }

    /// The row the last shift-arrow moved to, or the table's own idea of the last selected row.
    var keyboardRow: Int { trackedRange == nil ? selectedRow : cursorRow }

    /// The rows between anchor and cursor, as long as they are what is selected.
    private var trackedRange: IndexSet? {
        guard anchorRow >= 0, cursorRow >= 0 else { return nil }
        let range = IndexSet(integersIn: min(anchorRow, cursorRow)...max(anchorRow, cursorRow))
        return range == selectedRowIndexes ? range : nil
    }

    /// Shift-up and shift-down: the selection always runs from the anchor to the cursor, so going back the
    /// other way shrinks it. AppKit's own handling loses the anchor when the selection is set from the model.
    private func extendSelection(by step: Int) {
        guard numberOfRows > 0, let first = selectedRowIndexes.first, let last = selectedRowIndexes.last else { return }
        if trackedRange == nil {
            let contiguous = selectedRowIndexes.count == last - first + 1
            let current = selectedRowIndexes.contains(selectedRow) ? selectedRow : last
            cursorRow = current
            anchorRow = contiguous && current == first ? last : contiguous && current == last ? first : current
        }
        cursorRow = min(max(cursorRow + step, 0), numberOfRows - 1)
        selectRowIndexes(IndexSet(integersIn: min(anchorRow, cursorRow)...max(anchorRow, cursorRow)),
                         byExtendingSelection: false)
        scrollRowToVisible(cursorRow)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        let rows = selectedRowIndexes.contains(row) ? Array(selectedRowIndexes) : [row]
        return menuForRows?(rows)
    }

    override func mouseDown(with event: NSEvent) {
        anchorRow = -1; cursorRow = -1          // a click starts a new selection
        let start = convert(event.locationInWindow, from: nil)
        let row = row(at: start)
        let plain = event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty
        let wasOnlySelection = row >= 0 && selectedRowIndexes == IndexSet(integer: row)
        super.mouseDown(with: event)
        // A click on the row that is already selected selects nothing new, but should still play it.
        guard plain, wasOnlySelection, let up = NSApp.currentEvent, up.type == .leftMouseUp else { return }
        let end = convert(up.locationInWindow, from: nil)
        if hypot(end.x - start.x, end.y - start.y) < 4 { onReclick?(row) }
    }
}

@MainActor
final class LibraryListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let model: AppModel
    weak var table: LibraryNSTableView?
    var rowOfID: [Int64: Int] = [:]
    /// The Pool's lines, with folder headings (`.sample` holds an index into `model.visible`); nil for the plain list.
    var groupedRows: [PoolRow<Int>]?
    var joinedRows: [JoinedTableRow]?
    var expandedJoined = Set<Int64>()
    var joinedParts: [Int64: [JoinedPart]] = [:]
    var joinedRefreshVersion = 0
    var joinedRefreshTask: Task<Void, Never>?
    private var joinedLinksRevision = -1
    #if DEBUG
    var requestedJoinedSnapshot = false
    #endif
    var pool: PoolLayout?
    private var revision = -1
    private var shuffleSeed: UInt64?
    var changingSelection = false       // our own selection updates must not loop back into the model
    private var changingSort = false
    private static let hiddenKey = "libraryList.hiddenColumns"

    init(model: AppModel) { self.model = model }

    // MARK: building

    func makeTable() -> LibraryNSTableView {
        let table = LibraryNSTableView()
        self.table = table
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsTypeSelect = false
        table.floatsGroupRows = false
        table.rowHeight = 24
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)

        let hidden = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey)
                         ?? LibraryColumn.all.filter(\.hiddenByDefault).map(\.id))
        for spec in LibraryColumn.all {
            let column = NSTableColumn(identifier: .init(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = spec.minWidth
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true)
            column.resizingMask = spec.id == LibraryColumn.name ? [.autoresizingMask, .userResizingMask] : .userResizingMask
                        column.isHidden = hidden.contains(spec.id) && spec.id != LibraryColumn.name
            table.addTableColumn(column)
        }
        table.autosaveName = "LibraryList"
        table.autosaveTableColumns = true

        let headerMenu = NSMenu()
        headerMenu.delegate = self
        table.headerView?.menu = headerMenu

        table.menuForRows = { [weak self] rows in self?.menu(forRows: rows) }
        table.onKey = { [weak self] event in self?.handle(event) ?? false }
        table.onReclick = { [weak self] row in
            guard let self, let sample = self.sample(at: row) else { return }
            self.model.select(sample.id, play: true)
        }
        return table
    }

    // MARK: updating from the model

    func update(revision: Int, joinedLinksRevision: Int, selection: Set<Int64>,
                sortOrder: [KeyPathComparator<SampleRecord>], shuffleSeed: UInt64?, pool: PoolLayout?) {
        guard let table else { return }
        let linksChanged = joinedLinksRevision != self.joinedLinksRevision
        if linksChanged {
            self.joinedLinksRevision = joinedLinksRevision
            refreshExpandedJoinedParts(invalidate: true)
        }
        if revision != self.revision || pool != self.pool || linksChanged {
            self.revision = revision
            self.pool = pool
            rebuildRows()
            table.reloadData()
        } else {
            // Something a row shows changed without the list changing (drum tracks, search matches).
            let visible = table.rows(in: table.visibleRect)
            if visible.length > 0 {
                table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<visible.location + visible.length),
                                 columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
            }
        }
        applySelection(selection, in: table)
        applySort(sortOrder, in: table)
        if shuffleSeed != self.shuffleSeed {
            self.shuffleSeed = shuffleSeed
            table.scrollRowToVisible(0)          // a new order starts at the top of the list
        }
    }

    func applySelection(_ ids: Set<Int64>, in table: NSTableView) {
        var retained: [Int64: Int] = [:]
        for row in table.selectedRowIndexes {
            if let id = sample(at: row)?.id { retained[id] = row }
        }
        let rows = IndexSet(ids.compactMap { retained[$0] ?? rowOfID[$0] })
        guard rows != table.selectedRowIndexes else { return }
        changingSelection = true
        table.selectRowIndexes(rows, byExtendingSelection: false)
        changingSelection = false
    }

    private func applySort(_ order: [KeyPathComparator<SampleRecord>], in table: NSTableView) {
        guard let first = order.first, let column = LibraryColumn.column(for: first.keyPath) else { return }
        let wanted = NSSortDescriptor(key: column.id, ascending: first.order == .forward)
        guard table.sortDescriptors.first?.key != wanted.key || table.sortDescriptors.first?.ascending != wanted.ascending else { return }
        changingSort = true
        table.sortDescriptors = [wanted]
        changingSort = false
    }

    // MARK: data source

    func numberOfRows(in tableView: NSTableView) -> Int { groupedRows?.count ?? joinedRows?.count ?? model.visible.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let folder = folder(at: row) { return folderView(folder, in: tableView) }
        guard let tableColumn, let spec = LibraryColumn.column(id: tableColumn.identifier.rawValue) else { return nil }
        if let part = joinedPart(at: row), spec.id == LibraryColumn.name {
            return joinedPartView(part, in: tableView)
        }
        guard let sample = sample(at: row) else { return nil }
        switch spec.id {
        case LibraryColumn.name:
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? LibraryNameCell ?? LibraryNameCell()
            cell.identifier = tableColumn.identifier
            cell.configure(sample, drumTrack: model.drumTracks[sample.id], match: model.segmentMatches[sample.id],
                           joinedExpanded: sample.isJoined ? expandedJoined.contains(sample.id) : nil,
                           onToggle: { [weak self] in self?.toggleJoined(sample) })
            return cell
        default:
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? LibraryTextCell ?? LibraryTextCell()
            cell.identifier = tableColumn.identifier
            cell.configure(spec, sample: sample)
            return cell
        }
    }

    // MARK: selection and sorting

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !changingSelection, let table else { return }
        var seen = Set<Int64>()
        let ids = table.selectedRowIndexes.compactMap { sample(at: $0)?.id }.filter { seen.insert($0).inserted }
        if ids.count == 1 { model.select(ids[0], play: true); return }
        // Adding to a selection (shift or command click, shift-arrow) plays the sample that was just added.
        let added = Set(ids).subtracting(model.tableSelection)
        let newest = added.isEmpty ? nil : newestSample(among: added, in: table)
        model.tableSelection = Set(ids)
        if let newest { model.select(newest, play: true, keepSelection: true) }
    }

    /// The sample the person just picked: the one under the click, or for the keyboard the last row added.
    /// Dragging across rows does not play each one it passes.
    private func newestSample(among added: Set<Int64>, in table: NSTableView) -> Int64? {
        var row = -1
        if let event = NSApp.currentEvent {
            switch event.type {
            case .leftMouseDown: row = table.row(at: table.convert(event.locationInWindow, from: nil))
            case .keyDown: row = (table as? LibraryNSTableView)?.keyboardRow ?? table.selectedRow
            default: return nil
            }
        }
        guard row >= 0, let id = sample(at: row)?.id, added.contains(id) else { return nil }
        return id
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !changingSort, let descriptor = tableView.sortDescriptors.first, let key = descriptor.key,
              let column = LibraryColumn.column(id: key) else { return }
        model.sortOrder = [column.comparator(descriptor.ascending ? .forward : .reverse)]
    }

    // MARK: dragging out to a DAW

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        return sample(at: row)?.url as NSURL?
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                   forRowIndexes rowIndexes: IndexSet) {
        for row in rowIndexes { if let sample = sample(at: row) { model.registerGrab(sample.id) } }
    }

    // MARK: menus and keys

    private func menu(forRows rows: [Int]) -> NSMenu? {
        if rows.count == 1, let folder = folder(at: rows[0]), let pool {
            return NSMenu(entries: model.poolFolderMenu(drive: pool.drive, path: folder.folder.path))
        }
        let ids = rows.compactMap { sample(at: $0)?.id }
        let entries = model.sampleMenu(for: ids)
        return entries.isEmpty ? nil : NSMenu(entries: entries)
    }

    /// The heading's menu: tick the columns to show.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let table else { return }
        for spec in LibraryColumn.all where spec.id != LibraryColumn.name {
            let item = NSMenuItem(title: spec.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spec.id
            item.state = table.tableColumn(withIdentifier: .init(spec.id))?.isHidden == false ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func toggleColumn(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let column = table?.tableColumn(withIdentifier: .init(id)) else { return }
        column.isHidden.toggle()
        let hidden = LibraryColumn.all.filter { table?.tableColumn(withIdentifier: .init($0.id))?.isHidden == true }.map(\.id)
        UserDefaults.standard.set(hidden, forKey: Self.hiddenKey)
    }

    /// The same keys `RootView` binds, for when the list has the keyboard focus.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 49: model.togglePlayback(); return true                                      // space
        case 123: guard model.selectedID != nil else { return false }; model.sweep(-1); return true   // ←
        case 124: guard model.selectedID != nil else { return false }; model.sweep(1); return true    // →
        default: break
        }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else { return false }
        switch characters {
        case "f":
            guard !model.actionTargets.isEmpty else { return false }
            model.toggleFavorite(model.actionTargets); return true
        case "m":
            guard model.selectedID != nil else { return false }
            model.addCueAtMarker(); return true
        default:
            guard let number = Int(characters) else { return false }
            model.playCue(number: number); return true
        }
    }
}
