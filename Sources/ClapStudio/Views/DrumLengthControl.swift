import AppKit
import ClapCore
import SwiftUI

/// A typed bar count with native stepper buttons and Up/Down while editing.
struct DrumLengthControl: NSViewRepresentable {
    @Binding var bars: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ControlView {
        let view = ControlView()
        view.field.delegate = context.coordinator
        view.stepper.target = context.coordinator
        view.stepper.action = #selector(Coordinator.step(_:))
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: ControlView, context: Context) {
        context.coordinator.parent = self
        if view.field.currentEditor() == nil {
            view.field.integerValue = bars
            view.stepper.integerValue = bars
        }
    }

    final class ControlView: NSView {
        let field = NSTextField()
        let stepper = NSStepper()

        override init(frame: NSRect) {
            super.init(frame: frame)
            field.controlSize = .small
            field.bezelStyle = .roundedBezel
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            field.alignment = .right
            field.setAccessibilityLabel("Drum pattern length in bars")
            stepper.controlSize = .small
            stepper.minValue = 1
            stepper.maxValue = Double(DrumPattern.maxBars)
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.setAccessibilityLabel("Change drum pattern length")
            for control in [field, stepper] {
                control.translatesAutoresizingMaskIntoConstraints = false
                addSubview(control)
            }
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: leadingAnchor),
                field.widthAnchor.constraint(equalToConstant: 50),
                field.centerYAnchor.constraint(equalTo: centerYAnchor),
                stepper.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 4),
                stepper.trailingAnchor.constraint(equalTo: trailingAnchor),
                stepper.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DrumLengthControl
        weak var view: ControlView?
        init(_ parent: DrumLengthControl) { self.parent = parent }

        @objc func step(_ sender: NSStepper) { apply(sender.integerValue) }

        func controlTextDidChange(_ notification: Notification) {
            guard let view, let value = Int(view.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            view.stepper.integerValue = clamped(value)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            apply(Int(view?.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? parent.bars)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            let delta: Int
            switch command {
            case #selector(NSResponder.moveUp(_:)): delta = 1
            case #selector(NSResponder.moveDown(_:)): delta = -1
            default: return false
            }
            let value = Int(textView.string.trimmingCharacters(in: .whitespacesAndNewlines)) ?? parent.bars
            apply(clamped(value) + delta)
            return true
        }

        private func clamped(_ value: Int) -> Int { min(max(value, 1), DrumPattern.maxBars) }

        private func apply(_ value: Int) {
            let value = clamped(value)
            if value != parent.bars { parent.bars = value }
            view?.field.integerValue = value
            view?.field.currentEditor()?.string = String(value)
            view?.stepper.integerValue = value
        }
    }
}
