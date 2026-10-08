import AppKit

/// True while a text field has keyboard focus (its field editor is the first responder),
/// so single-key shortcuts such as digits for cues must leave the keystroke alone.
@MainActor
var isTypingInTextField: Bool {
    NSApp.keyWindow?.firstResponder is NSTextView
}
