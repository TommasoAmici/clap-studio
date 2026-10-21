import ClapCore
import SwiftUI

/// One bar of the piano roll's grid: the rows, the beat lines and the notes that fall in it. The roll is a lazy row
/// of these, so a long melody only draws the bars on screen, and each is redrawn only when something in it changes.
struct PianoRollBar: View, Equatable {
    let bar: Int
    let isLast: Bool
    let grid: PianoRollGrid
    let pattern: MelodyPattern
    let trackIndex: Int
    let selected: UUID?

    var body: some View {
        let first = Double(bar * MelodyPattern.stepsPerBar)
        let last = first + Double(MelodyPattern.stepsPerBar)
        let colour = melodyTrackColors[trackIndex % melodyTrackColors.count]
        Canvas { context, size in
            for pitch in 0..<PianoRollGrid.rows {
                let row = CGRect(x: 0, y: grid.y(ofPitch: pitch), width: size.width, height: grid.rowHeight)
                if NoteNames.isBlackKey(pitch) { context.fill(Path(row), with: .color(.black.opacity(0.14))) }
                if pitch % 12 == 0 { context.fill(Path(CGRect(x: 0, y: row.maxY - 0.5, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.5))) }
            }
            for step in 0...MelodyPattern.stepsPerBar where step < MelodyPattern.stepsPerBar || isLast {
                let strength = step % 16 == 0 ? 0.55 : step % 4 == 0 ? 0.3 : 0.12
                let x = grid.x(ofStep: Double(step))
                context.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(.secondary.opacity(strength)))
            }
            // The other tracks, faintly, to write against.
            for (index, other) in pattern.tracks.enumerated() where index != trackIndex {
                for note in other.notes where note.end > first && note.start < last {
                    fill(note, from: first, in: &context, colour: melodyTrackColors[index % melodyTrackColors.count].opacity(0.28))
                }
            }
            guard pattern.tracks.indices.contains(trackIndex) else { return }
            for note in pattern.tracks[trackIndex].notes where note.end > first && note.start < last {
                fill(note, from: first, in: &context, colour: colour.opacity(0.35 + 0.65 * Double(note.velocity)))
                if note.id == selected {
                    let f = grid.frame(of: note)
                    context.stroke(Path(roundedRect: CGRect(x: f.x - grid.x(ofStep: first), y: f.y, width: f.width, height: f.height), cornerRadius: 2),
                                   with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }

    /// Draws a note, shifted so the bar's own start is at x = 0 (a note crossing into the next bar is cut by the canvas).
    private func fill(_ note: MelodyNote, from first: Double, in context: inout GraphicsContext, colour: Color) {
        let f = grid.frame(of: note)
        let x = f.x - grid.x(ofStep: first)
        context.fill(Path(roundedRect: CGRect(x: x, y: f.y + 0.5, width: max(2, f.width - 0.5), height: f.height - 1), cornerRadius: 2), with: .color(colour))
    }
}

/// The line that moves along the roll while the melody plays. It is its own view so each step redraws only this line.
/// While playing it also turns the window to the bar the melody has reached, so a long melody can be followed.
struct PlayheadLine: View {
    @Environment(AppModel.self) private var model
    let grid: PianoRollGrid
    let left: Double
    let width: Double
    @Binding var scroll: Double
    let maxScroll: Double

    var body: some View {
        Group {
            if let step = model.melodyStep, grid.x(ofStep: Double(step) - left) >= 0, grid.x(ofStep: Double(step) - left) < width {
                Rectangle().fill(Color.white.opacity(0.85))
                    .frame(width: 1.5, height: grid.height)
                    .offset(x: grid.x(ofStep: Double(step) - left))
            }
        }
        .allowsHitTesting(false)
        .onChange(of: model.melodyStep) { _, step in
            guard let step, maxScroll > 0 else { return }
            let x = grid.x(ofStep: Double(step) - left)
            if x < 0 || x >= width {
                let bar = Double(MelodyPattern.stepsPerBar)
                scroll = min(maxScroll, (Double(step) / bar).rounded(.down) * bar)
            }
        }
    }
}

/// Moves a view's content sideways when the pointer is over it and the user scrolls sideways (a trackpad swipe, or
/// Shift with a wheel). Up-and-down scrolling is left to whatever scroll view is underneath.
struct SidewaysScroll: NSViewRepresentable {
    /// Called with how far the content was dragged, in points: positive moves it to the right.
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: ((Double) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.take(event) ?? event }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        private func take(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
            let shifted = event.modifierFlags.contains(.shift)
            let across = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : (shifted ? event.scrollingDeltaY : 0)
            guard across != 0, abs(across) >= abs(event.scrollingDeltaY) || shifted else { return event }
            onScroll?(Double(across))
            return nil
        }
    }
}
