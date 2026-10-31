import Foundation

/// A block of the library sidebar. The raw value is what is stored in the preferences, so it never changes.
public enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case filters, collections, categories, moods, tags
    /// The sticks of the Squid Salmple, only listed while one is connected.
    case usbDrives
    case folders

    public var id: String { rawValue }

    /// The section that lists a sidebar selection, from the tag the selection is stored under (`AppModel.sidebarTag`).
    public static func containing(tag: String) -> SidebarSection {
        if tag.hasPrefix("smart.") { return .filters }
        if tag.hasPrefix("col.") { return .collections }
        if tag.hasPrefix("cat.") { return .categories }
        if tag.hasPrefix("mood.") { return .moods }
        if tag.hasPrefix("tag.") { return .tags }
        if tag.hasPrefix("usb\u{1F}") { return .usbDrives }
        return .folders
    }
}

/// Which sidebar sections are listed, in what order, and which are folded: what the musician set up, kept in the
/// preferences. It copes with ids it does not know (written by another version) and with sections added later.
public struct SidebarLayout: Equatable, Sendable {
    /// Every section exactly once, top to bottom.
    public private(set) var order: [SidebarSection]
    /// Sections the musician chose not to list.
    public private(set) var hidden: Set<SidebarSection>
    /// Sections shown as a title only; their rows are one click away.
    public private(set) var collapsed: Set<SidebarSection>

    public static let orderKey = "sidebar.order"
    public static let hiddenKey = "sidebar.hidden"
    public static let collapsedKey = "sidebar.collapsed"

    public init(order: [String] = [], hidden: [String] = [], collapsed: [String] = []) {
        self.order = Self.complete(order)
        self.hidden = Set(hidden.compactMap(SidebarSection.init(rawValue:)))
        self.collapsed = Set(collapsed.compactMap(SidebarSection.init(rawValue:)))
    }

    /// Stored ids that are known, once each, then the sections that are missing, each next to the one before it by default.
    private static func complete(_ stored: [String]) -> [SidebarSection] {
        var result: [SidebarSection] = []
        for section in stored.compactMap(SidebarSection.init(rawValue:)) where !result.contains(section) { result.append(section) }
        let all = SidebarSection.allCases
        for (index, section) in all.enumerated() where !result.contains(section) {
            if index > 0, let before = result.firstIndex(of: all[index - 1]) { result.insert(section, at: before + 1) }
            else { result.insert(section, at: 0) }
        }
        return result
    }

    public var isDefault: Bool { order == SidebarSection.allCases && hidden.isEmpty }
    public func isHidden(_ section: SidebarSection) -> Bool { hidden.contains(section) }
    public func isCollapsed(_ section: SidebarSection) -> Bool { collapsed.contains(section) }

    /// The sections to list: in order, without the hidden ones, and only those that have something to show now.
    public func shown(available: Set<SidebarSection>) -> [SidebarSection] {
        order.filter { available.contains($0) && !hidden.contains($0) }
    }

    public mutating func setHidden(_ section: SidebarSection, _ isHidden: Bool) {
        if isHidden { hidden.insert(section) } else { hidden.remove(section) }
    }

    public mutating func setCollapsed(_ section: SidebarSection, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(section) } else { collapsed.remove(section) }
    }

    /// Moves entries of `order` as a list does when dragged (`offset` counts positions before the move).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter { order.indices.contains($0) }.map { order[$0] }
        let before = source.filter { $0 < destination }.count
        var rest = order
        for index in source.sorted(by: >) where rest.indices.contains(index) { rest.remove(at: index) }
        rest.insert(contentsOf: moving, at: max(0, min(rest.count, destination - before)))
        order = rest
    }

    /// Moves a section one place up (-1) or down (1) among the sections that are listed, jumping over hidden ones.
    public mutating func move(_ section: SidebarSection, by step: Int, among listed: [SidebarSection]) {
        guard let position = listed.firstIndex(of: section), listed.indices.contains(position + step),
              let from = order.firstIndex(of: section), let to = order.firstIndex(of: listed[position + step]) else { return }
        order.remove(at: from)
        order.insert(section, at: to)
    }

    /// Lists every section again in the default order. What is folded is left as it is.
    public mutating func reset() {
        order = SidebarSection.allCases
        hidden = []
    }

    // MARK: preferences

    public static func load(from defaults: UserDefaults = .standard) -> SidebarLayout {
        SidebarLayout(order: defaults.stringArray(forKey: orderKey) ?? [], hidden: defaults.stringArray(forKey: hiddenKey) ?? [],
                      collapsed: defaults.stringArray(forKey: collapsedKey) ?? [])
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(SidebarSection.allCases.filter(hidden.contains).map(\.rawValue), forKey: Self.hiddenKey)
        defaults.set(SidebarSection.allCases.filter(collapsed.contains).map(\.rawValue), forKey: Self.collapsedKey)
    }
}
