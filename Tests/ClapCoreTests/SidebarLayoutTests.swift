import Foundation
import Testing
@testable import ClapCore

@Suite struct SidebarLayoutTests {
    private func defaults() -> UserDefaults {
        let name = "clap-sidebar-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func withoutAnyChoiceSectionsFollowTheDefaultOrderAndAreOpen() {
        let layout = SidebarLayout()
        #expect(layout.order == [.filters, .collections, .categories, .moods, .tags, .usbDrives, .folders])
        #expect(layout.hidden.isEmpty && layout.collapsed.isEmpty, "Nothing is hidden or folded until the musician does it.")
        #expect(layout.isDefault)
    }

    @Test func aStoredOrderIsKept() {
        let layout = SidebarLayout(order: ["folders", "tags", "filters", "collections", "categories", "moods", "usbDrives"])
        #expect(layout.order.first == .folders && layout.order[1] == .tags && layout.order.count == 7)
        #expect(!layout.isDefault)
    }

    @Test func unknownAndRepeatedIdsAreIgnored() {
        let layout = SidebarLayout(order: ["nonsense", "tags", "tags", "filters"], hidden: ["gone", "moods"], collapsed: ["", "folders", "later"])
        #expect(layout.order == [.tags, .usbDrives, .folders, .filters, .collections, .categories, .moods],
                "Ids this version does not know, and repeats, are dropped; missing sections follow their default neighbour.")
        #expect(Set(layout.order) == Set(SidebarSection.allCases) && layout.order.count == SidebarSection.allCases.count,
                "Every section is listed exactly once, so none can be lost.")
        #expect(layout.hidden == [.moods] && layout.collapsed == [.folders])
    }

    @Test func aSectionAddedLaterJoinsNextToItsDefaultNeighbour() {
        // An order saved before the USB section existed.
        let layout = SidebarLayout(order: ["tags", "folders", "filters", "collections", "categories", "moods"])
        #expect(layout.order == [.tags, .usbDrives, .folders, .filters, .collections, .categories, .moods],
                "The new section lands after the section that precedes it by default, not at an odd end of the list.")
    }

    @Test func aPartialOrderIsCompletedInDefaultOrder() {
        let layout = SidebarLayout(order: ["folders", "filters"])
        #expect(layout.order == [.folders, .filters, .collections, .categories, .moods, .tags, .usbDrives])
    }

    @Test func shownLeavesOutHiddenAndUnavailableSections() {
        var layout = SidebarLayout()
        layout.setHidden(.moods, true)
        let shown = layout.shown(available: [.filters, .collections, .moods, .folders])
        #expect(shown == [.filters, .collections, .folders], "Moods is hidden by choice, the others are missing because there is nothing to show.")
        #expect(layout.shown(available: Set(SidebarSection.allCases)).contains(.moods) == false)
        layout.setHidden(.moods, false)
        #expect(layout.shown(available: [.moods]) == [.moods])
    }

    @Test func foldingASectionIsRememberedPerSection() {
        var layout = SidebarLayout()
        layout.setCollapsed(.tags, true)
        #expect(layout.isCollapsed(.tags) && !layout.isCollapsed(.moods))
        layout.setCollapsed(.tags, false)
        #expect(!layout.isCollapsed(.tags))
    }

    @Test func draggingAnEntryMovesItLikeAList() {
        var layout = SidebarLayout()
        layout.move(fromOffsets: IndexSet(integer: 6), toOffset: 0)      // Folders to the top
        #expect(layout.order == [.folders, .filters, .collections, .categories, .moods, .tags, .usbDrives])
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)      // and down below Collections
        #expect(layout.order == [.filters, .collections, .folders, .categories, .moods, .tags, .usbDrives])
        layout.move(fromOffsets: IndexSet([0, 1]), toOffset: 7)          // the first two to the end
        #expect(layout.order == [.folders, .categories, .moods, .tags, .usbDrives, .filters, .collections])
    }

    @Test func movingUpAndDownJumpsOverHiddenSections() {
        var layout = SidebarLayout()
        layout.setHidden(.categories, true)
        let shown = layout.shown(available: Set(SidebarSection.allCases))
        layout.move(.moods, by: -1, among: shown)
        #expect(layout.order.prefix(3) == [.filters, .moods, .collections],
                "Categories is hidden, so Moods moves above Collections, the section shown above it.")
        layout.move(.folders, by: 1, among: layout.shown(available: Set(SidebarSection.allCases)))
        #expect(layout.order.last == .folders, "The last section cannot move down.")
        layout.move(.filters, by: -1, among: layout.shown(available: Set(SidebarSection.allCases)))
        #expect(layout.order.first == .filters, "The first section cannot move up.")
    }

    @Test func resetBringsBackOrderAndHiddenSectionsButKeepsWhatIsFolded() {
        var layout = SidebarLayout(order: ["folders"], hidden: ["tags"], collapsed: ["moods"])
        layout.reset()
        #expect(layout.order == SidebarSection.allCases && layout.hidden.isEmpty)
        #expect(layout.collapsed == [.moods], "Reset is about what is listed and where; folded sections stay folded.")
    }

    @Test func theLayoutSurvivesARestart() {
        let store = defaults()
        var layout = SidebarLayout()
        layout.move(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        layout.setHidden(.tags, true)
        layout.setCollapsed(.folders, true)
        layout.save(to: store)
        #expect(SidebarLayout.load(from: store) == layout)
        #expect(store.stringArray(forKey: "sidebar.order")?.first == "usbDrives")
        #expect(store.stringArray(forKey: "sidebar.hidden") == ["tags"] && store.stringArray(forKey: "sidebar.collapsed") == ["folders"])
    }

    @Test func missingOrDamagedPreferencesGiveTheDefaultLayout() {
        let store = defaults()
        #expect(SidebarLayout.load(from: store).isDefault)
        store.set(42, forKey: "sidebar.order")
        store.set(["a": 1], forKey: "sidebar.hidden")
        store.set("tags", forKey: "sidebar.collapsed")
        #expect(SidebarLayout.load(from: store).isDefault, "A value of the wrong kind is ignored rather than crashing the sidebar.")
    }

    @Test func aSelectionBelongsToTheSectionThatListsIt() {
        #expect(SidebarSection.containing(tag: "smart.Favorites") == .filters)
        #expect(SidebarSection.containing(tag: "col.12") == .collections)
        #expect(SidebarSection.containing(tag: "cat.Kick") == .categories)
        #expect(SidebarSection.containing(tag: "mood.Dreamy") == .moods)
        #expect(SidebarSection.containing(tag: "tag.warm") == .tags)
        #expect(SidebarSection.containing(tag: "usb\u{1F}pool\u{1F}\u{1F}drive") == .usbDrives)
        #expect(SidebarSection.containing(tag: "3|Drums/Kicks") == .folders, "Anything else is a folder of the library.")
    }
}
