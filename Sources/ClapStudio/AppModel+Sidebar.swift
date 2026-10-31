import ClapCore
import Foundation

/// Which sidebar sections can be listed, and hiding them.
extension AppModel {
    private static let allSamplesTag = "smart.\(SmartFilter.all.rawValue)"

    /// Sections that have something to show now: categories and the like only once the library has some, the sticks only
    /// while one is connected. Hidden sections are left out by `SidebarLayout.shown`.
    var availableSidebarSections: Set<SidebarSection> {
        var available: Set<SidebarSection> = [.filters, .collections, .folders]
        if !categoryCounts.isEmpty { available.insert(.categories) }
        if !moodCounts.isEmpty { available.insert(.moods) }
        if !tagCounts.isEmpty { available.insert(.tags) }
        if squidEnabled { available.insert(.usbDrives) }
        return available
    }

    /// The sections in the sidebar now, top to bottom.
    var listedSidebarSections: [SidebarSection] { sidebarLayout.shown(available: availableSidebarSections) }

    /// Hides or shows a section. Hiding the one that holds the current selection goes back to All Samples, so the list
    /// never shows a filter that has no row left to explain it.
    func setSidebar(_ section: SidebarSection, hidden: Bool) {
        sidebarLayout.setHidden(section, hidden)
        if hidden, SidebarSection.containing(tag: sidebarTag) == section, sidebarTag != Self.allSamplesTag {
            selectSidebar(Self.allSamplesTag)
        }
    }

    func moveSidebar(_ section: SidebarSection, by step: Int) {
        sidebarLayout.move(section, by: step, among: listedSidebarSections)
    }
}
