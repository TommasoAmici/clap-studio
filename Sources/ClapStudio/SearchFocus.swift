import AppKit

/// Moves keyboard focus to the search field in the window's toolbar (Cmd+F) on macOS 14, which has no
/// `searchFocused`: the field is found among the window's views.
@MainActor
enum SearchFocus {
    static let placeholderPrefix = "Search by name"

    /// False when the window has no search field to focus.
    @discardableResult
    static func focus() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible),
              let root = window.contentView?.superview ?? window.contentView,
              let field = searchField(in: root) else { return false }
        window.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        return true
    }

    static func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.placeholderString?.hasPrefix(placeholderPrefix) == true { return field }
        for sub in view.subviews { if let found = searchField(in: sub) { return found } }
        return nil
    }
}
