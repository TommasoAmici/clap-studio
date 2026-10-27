import AppKit

/// Keeps long release notes readable without moving the update buttons off-screen.
@MainActor enum UpdateReleaseNotes {
    static func view(for notes: String) -> NSView {
        if notes.isEmpty {
            let label = NSTextField(wrappingLabelWithString: "Release notes are not available for this update.")
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: 0, width: 380, height: 36)
            return label
        }
        let width: CGFloat = 380, height: CGFloat = 190
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height + 24))
        let heading = NSTextField(labelWithString: "Release notes")
        heading.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        heading.frame = NSRect(x: 0, y: height + 6, width: width, height: 18)
        container.addSubview(heading)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setAccessibilityLabel("Release notes")
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isSelectable = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.backgroundColor = .textBackgroundColor
        text.setAccessibilityLabel("Release notes")
        text.textStorage?.setAttributedString(formatted(notes))
        scroll.documentView = text
        container.addSubview(scroll)
        return container
    }

    private static func formatted(_ notes: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 5
        for line in notes.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var words = line
            let isHeading = words.range(of: #"^#{1,6}\s+"#, options: .regularExpression) != nil
            if isHeading {
                words = words.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            } else {
                words = words.replacingOccurrences(of: #"^(\s*)[-*+]\s+"#, with: "$1• ", options: .regularExpression)
            }
            let parsed = (try? NSAttributedString(markdown: words, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? NSAttributedString(string: words)
            let row = NSMutableAttributedString(attributedString: parsed)
            row.append(NSAttributedString(string: "\n"))
            let range = NSRange(location: 0, length: row.length)
            row.removeAttribute(.link, range: range)
            row.addAttributes([.font: isHeading ? NSFont.systemFont(ofSize: 13, weight: .semibold) : NSFont.systemFont(ofSize: 12),
                               .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: range)
            result.append(row)
        }
        return result
    }
}
