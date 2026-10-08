import AppKit

/// Moves keyboard focus to the search field in the window's toolbar (Cmd+F), selecting what is typed there.
@MainActor
enum SearchFocus {
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

    static func searchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for sub in view.subviews { if let found = searchField(in: sub) { return found } }
        return nil
    }
}
