import AppKit
import ClapCore
import SwiftUI

/// One line of the right-click menu for samples. Described as data so the library list (SwiftUI) and the
/// map (an AppKit view) show exactly the same menu.
indirect enum SampleMenuEntry {
    case action(String, () -> Void)
    case submenu(String, [SampleMenuEntry])
    case divider
}

extension AppModel {
    func sampleMenu(for ids: [Int64]) -> [SampleMenuEntry] {
        let samples = ids.compactMap { sampleByID[$0] }
        guard let first = samples.first else { return [] }
        var menu: [SampleMenuEntry] = []
        if ids.count == 1 {
            menu.append(.action("Find Similar Sounds") { [unowned self] in showSimilar(to: first.id) })
            menu.append(.action("Build a Kit From This…") { [unowned self] in buildKit(around: first.id) })
        }
        menu.append(.action("Add to Drum Machine") { [unowned self] in addToDrums(ids) })
        if squidEnabled { menu.append(.action("Send to Squid…") { [unowned self] in openSquidExport(ids: ids) }) }
        menu.append(.action("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(samples.map(\.url)) })
        menu.append(.divider)
        menu.append(.action(samples.allSatisfy(\.favorite) ? "Remove from Favorites" : "Add to Favorites") { [unowned self] in toggleFavorite(ids) })
        var collectionItems = collections.map { c in SampleMenuEntry.action(c.name) { [unowned self] in add(ids, toCollection: c.id) } }
        if !collectionItems.isEmpty { collectionItems.append(.divider) }
        collectionItems.append(.action("New Collection…") { [unowned self] in newCollectionSeed = ids })
        menu.append(.submenu("Add to Collection", collectionItems))
        if let current = collectionSelection {
            menu.append(.action("Remove from This Collection") { [unowned self] in remove(ids, fromCollection: current) })
        }
        menu.append(.action("Add Tag…") { [unowned self] in tagPromptTargets = ids })
        menu.append(.action("Copy To…") { [unowned self] in openExport(ids: ids) })
        menu.append(.divider)
        if samples.allSatisfy(\.hidden) {
            menu.append(.action("Show in Library Again") { [unowned self] in unhide(ids) })
        } else {
            menu.append(.action("Hide from Library") { [unowned self] in hide(ids) })
        }
        return menu
    }
}

/// Draws menu entries in SwiftUI.
struct SampleMenuContent: View {
    let entries: [SampleMenuEntry]

    var body: some View {
        ForEach(entries.indices, id: \.self) { index in
            switch entries[index] {
            case .action(let title, let run): Button(title, action: run)
            case .submenu(let title, let items): Menu(title) { SampleMenuContent(entries: items) }
            case .divider: Divider()
            }
        }
    }
}

/// Draws menu entries in AppKit.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

extension NSMenu {
    convenience init(entries: [SampleMenuEntry]) {
        self.init()
        autoenablesItems = false
        for entry in entries {
            switch entry {
            case .action(let title, let run): addItem(ClosureMenuItem(title: title, run: run))
            case .divider: addItem(.separator())
            case .submenu(let title, let items):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = NSMenu(entries: items)
                addItem(item)
            }
        }
    }
}
