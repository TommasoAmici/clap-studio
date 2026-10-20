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
        menu.append(.action("Add to Melody") { [unowned self] in addToMelody(ids) })
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
        var categoryItems = SoundCategories.names.map { name in
            SampleMenuEntry.action(name) { [unowned self] in setCategory(ids, name) }
        }
        if samples.contains(where: { $0.categoryManual != nil }) {
            categoryItems.append(.divider)
            categoryItems.append(.action("Use Automatic") { [unowned self] in setCategory(ids, nil) })
        }
        menu.append(.submenu("Set Category", categoryItems))
        var moodItems: [SampleMenuEntry] = []
        let present = SoundMoods.names.filter { name in samples.contains { $0.moods.contains(name) } }
        moodItems.append(.submenu("Add", SoundMoods.names.map { name in
            .action(name) { [unowned self] in changeMoods(ids, named: "Add Mood \(name)") { $0.contains(name) ? $0 : $0 + [name] } }
        }))
        if !present.isEmpty {
            moodItems.append(.submenu("Remove", present.map { name in
                .action(name) { [unowned self] in changeMoods(ids, named: "Remove Mood \(name)") { $0.filter { $0 != name } } }
            }))
        }
        moodItems.append(.action("Clear") { [unowned self] in changeMoods(ids, named: "Clear Moods") { _ in [] } })
        if samples.contains(where: { $0.moodsManual != nil }) {
            moodItems.append(.divider)
            moodItems.append(.action("Use Automatic") { [unowned self] in changeMoods(ids, named: "Use Automatic Moods") { _ in nil } })
        }
        menu.append(.submenu("Set Mood", moodItems))
        menu.append(.action("Add Tag…") { [unowned self] in tagPromptTargets = ids })
        menu.append(.action("Tags from File Keywords") { [unowned self] in importFileKeywords(ids) })
        if samples.contains(where: canWriteTags) {
            menu.append(.action("Write Tags into Files…") { [unowned self] in tagWriteTargets = ids.filter { sampleByID[$0].map(canWriteTags) == true } })
        }
        menu.append(.action("Copy To…") { [unowned self] in openExport(ids: ids) })
        menu.append(.divider)
        let poolEntries = samples.compactMap { poolEntry(of: $0) }
        if poolEntries.count == samples.count {
            menu.append(.action("Move to Trash") { [unowned self] in trashPoolEntries(poolEntries) })
            menu.append(.divider)
        }
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
