import AppKit
import ClapCore

// MARK: - cells

/// The name, with the icon for what the sample is and the badges that go with it.
final class LibraryNameCell: NSTableCellView {
    private let disclosure = NSButton()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let match = PillLabel()
    private let star = NSImageView()
    private let spinner = NSProgressIndicator()
    private var onToggle: (() -> Void)?

    init() {
        super.init(frame: .zero)
        disclosure.isBordered = false
        disclosure.target = self
        disclosure.action = #selector(toggleJoined)
        disclosure.imagePosition = .imageOnly
        disclosure.setContentHuggingPriority(.required, for: .horizontal)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        star.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")
        star.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        star.contentTintColor = .systemYellow
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isIndeterminate = true
        let stack = NSStackView(views: [disclosure, icon, label, match, star, spinner])
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -3),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = label
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func toggleJoined() { onToggle?() }

    func configure(_ sample: SampleRecord, drumTrack: Int?, match found: SegmentMatch?,
                   joinedExpanded: Bool?, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        disclosure.isHidden = joinedExpanded == nil
        if let joinedExpanded {
            disclosure.image = NSImage(systemSymbolName: joinedExpanded ? "chevron.down" : "chevron.right",
                                       accessibilityDescription: joinedExpanded ? "Collapse joined sample" : "Expand joined sample")
            disclosure.setAccessibilityLabel(joinedExpanded ? "Collapse joined sample" : "Expand joined sample")
            disclosure.toolTip = joinedExpanded ? "Hide source samples" : "Show source samples"
        }
        label.stringValue = sample.name
        if let drumTrack {
            icon.image = NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: "Loaded in the drum machine")
            icon.contentTintColor = .systemOrange
            icon.toolTip = "Loaded in the drum machine (track \(drumTrack))"
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.22).cgColor
        } else {
            icon.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
            icon.toolTip = nil
            layer?.backgroundColor = nil
        }
        if let found {
            match.set("at \(Format.timestamp(found.start))", tip: "Best match in this recording")
            match.isHidden = false
        } else { match.isHidden = true }
        star.isHidden = !sample.favorite
        if sample.status == .pending { spinner.isHidden = false; spinner.startAnimation(nil) }
        else { spinner.isHidden = true; spinner.stopAnimation(nil) }
    }
}

/// A single line of text in a column; the uses column gets a tinted badge behind it.
final class LibraryTextCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let badge = NSView()

    init() {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        addSubview(badge)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -5),
            badge.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 5),
            badge.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 16),
        ])
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ spec: LibraryColumn, sample: SampleRecord) {
        label.stringValue = spec.text(sample)
        label.font = spec.monospacedDigits ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                                           : .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = spec.truncatesHead ? .byTruncatingHead : .byTruncatingTail
        let used = spec.id == LibraryColumn.uses && sample.useCount > 0
        label.textColor = spec.id == LibraryColumn.uses && !used ? .tertiaryLabelColor : .secondaryLabelColor
        badge.isHidden = !used
        if used {
            badge.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(min(0.15 + Double(sample.useCount) * 0.05, 0.6)).cgColor
        }
    }
}

/// Small rounded tag, like the "at 2:05" shown next to a field recording that matched a search.
private final class PillLabel: NSView {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func set(_ text: String, tip: String) {
        label.stringValue = text
        toolTip = tip
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
    }

    override var wantsUpdateLayer: Bool { true }
}
