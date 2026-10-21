import AppKit
import ClapCore
import SwiftUI

/// Colours that tell the melody's tracks apart, in track order.
let melodyTrackColors: [Color] = [.accentColor, .orange, .green, .pink]

/// The piano roll of one melody track: a keyboard on the left and a grid of steps. Click to add a note, drag it to
/// move it, drag its right edge to stretch it, click a note again (or press Delete) to remove it.
struct PianoRoll: View {
    @Environment(AppModel.self) private var model
    let trackIndex: Int
    @State private var drag: Drag?
    @State private var gestureBegan = false
    @State private var didMove = false
    @State private var pressedKey: Int?               // the piano key being held
    @State private var clickedNote: UUID?             // the note under the pointer when it went down, if any
    @State private var lastLength = 2.0               // new notes are as long as the last one drawn
    @State private var scroll = 0.0                   // the step at the left edge of the grid, for melodies wider than the roll
    @State private var gestureScroll = 0.0            // `scroll` when the current click or drag began
    @FocusState private var focused: Bool

    private static let keyboardWidth: CGFloat = 46
    private static let rowHeight = 12.0
    private static let minStepWidth = 10.0

    private enum Drag {
        case move(id: UUID, grabbedAt: Double)      // how far into the note (in steps) it was picked up
        case stretch(id: UUID)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width - Self.keyboardWidth)
            let total = Double(model.melodyPattern.stepCount)
            let grid = PianoRollGrid(stepWidth: max(Self.minStepWidth, width / total), rowHeight: Self.rowHeight)
            let maxScroll = max(0, total - width / grid.stepWidth)
            let left = min(max(0, scroll), maxScroll)
            VStack(spacing: 0) {
                // The keyboard sits inside the vertical scroll beside the grid, so the two always line up.
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            keyboard(grid).frame(width: Self.keyboardWidth, height: grid.height)
                            gridView(grid, width: width, left: left, maxScroll: maxScroll)
                        }
                        .overlay(alignment: .topLeading) { rowAnchors(grid) }
                    }
                    .onAppear { reveal(proxy, grid) }
                    .onChange(of: trackIndex) { reveal(proxy, grid) }
                }
                // A melody longer than the roll is shown a window at a time: this slider, or a sideways scroll, moves it.
                if maxScroll > 0 {
                    Slider(value: Binding(get: { left }, set: { scroll = $0 }), in: 0...maxScroll)
                        .controlSize(.mini).padding(.leading, Self.keyboardWidth).padding(.trailing, 8)
                        .help("Move along the melody")
                }
            }
            .background(SidewaysScroll { points in scroll = min(max(0, left - points / grid.stepWidth), maxScroll) })
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in model.deleteSelectedMelodyNote(); return .handled }
        .onKeyPress(.space) { model.toggleDrumPlayback(); return .handled }
    }

    // MARK: drawing

    private func keyboard(_ grid: PianoRollGrid) -> some View {
        Canvas { context, size in
            for pitch in 0..<PianoRollGrid.rows {
                let y = grid.y(ofPitch: pitch)
                let key = CGRect(x: 0, y: y, width: size.width, height: grid.rowHeight)
                let black = NoteNames.isBlackKey(pitch)
                context.fill(Path(key), with: .color(black ? Color(white: 0.16) : Color(white: 0.92)))
                context.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(.black.opacity(0.25)))
                if pitch % 12 == 0 {
                    context.draw(Text(NoteNames.name(midi: pitch)).font(.system(size: 9, weight: .semibold)).foregroundColor(.black.opacity(0.7)),
                                 at: CGPoint(x: size.width - 4, y: y + grid.rowHeight / 2), anchor: .trailing)
                }
            }
        }
        .background(.bar)
        .overlay(alignment: .topLeading) {
            // The key under the pointer lights up while it is held.
            if let pressed = pressedKey {
                Rectangle().fill(Color.accentColor.opacity(0.55))
                    .frame(height: grid.rowHeight).offset(y: grid.y(ofPitch: pressed)).allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(playingKeys(grid))
        .help("Click a key to hear it with this track's sound")
    }

    /// Pressing a key sounds it; sliding to another key while held plays that one too.
    private func playingKeys(_ grid: PianoRollGrid) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let pitch = grid.pitch(atY: value.location.y)
                guard pitch != pressedKey else { return }
                pressedKey = pitch
                model.auditionMelodyKey(pitch)
            }
            .onEnded { _ in pressedKey = nil }
    }

    /// Only the bars inside the roll are built, however long the melody is. One gesture covers them all, in the
    /// grid's own coordinates (the left edge of the window is step `left`).
    private func gridView(_ grid: PianoRollGrid, width: Double, left: Double, maxScroll: Double) -> some View {
        let pattern = model.melodyPattern
        let barSteps = Double(MelodyPattern.stepsPerBar)
        let first = min(Int(left / barSteps), pattern.bars - 1)
        let last = max(first, min(Int((left + width / grid.stepWidth) / barSteps), pattern.bars - 1))
        let selected = model.selectedMelodyNote
        return HStack(spacing: 0) {
            ForEach(first...last, id: \.self) { bar in
                PianoRollBar(bar: bar, isLast: bar == pattern.bars - 1, grid: grid, pattern: pattern,
                             trackIndex: trackIndex, selected: selected)
                    .equatable()
                    .frame(width: grid.x(ofStep: barSteps), height: grid.height)
            }
        }
        .offset(x: -grid.x(ofStep: left - Double(first) * barSteps))
        .frame(width: width, height: grid.height, alignment: .leading)
        .clipped()
        .overlay(alignment: .topLeading) { PlayheadLine(grid: grid, left: left, width: width, scroll: $scroll, maxScroll: maxScroll) }
        .contentShape(Rectangle())
        .gesture(drawing(grid, left: left))
    }

    /// Invisible markers, one per row, so the roll can scroll to the notes it holds.
    private func rowAnchors(_ grid: PianoRollGrid) -> some View {
        VStack(spacing: 0) {
            ForEach((0..<PianoRollGrid.rows).reversed(), id: \.self) { pitch in
                Color.clear.frame(width: 1, height: grid.rowHeight).id(pitch)
            }
        }
        .allowsHitTesting(false)
    }

    /// Scrolls so the track's notes (or its root note, while empty) sit in the middle.
    private func reveal(_ proxy: ScrollViewProxy, _ grid: PianoRollGrid) {
        guard let track = model.currentMelodyTrack else { return }
        let pitches = track.notes.map(\.pitch)
        let middle = pitches.isEmpty ? track.rootNote : (pitches.min()! + pitches.max()!) / 2
        DispatchQueue.main.async { proxy.scrollTo(middle, anchor: .center) }
    }

    // MARK: editing

    /// Points in the gesture are measured from the window's left edge; the grid works from the start of the melody.
    private func inGrid(_ point: CGPoint, _ grid: PianoRollGrid) -> CGPoint {
        CGPoint(x: point.x + grid.x(ofStep: gestureScroll), y: point.y)
    }

    private func drawing(_ grid: PianoRollGrid, left: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil && !gestureBegan {
                    gestureBegan = true; didMove = false; gestureScroll = left
                    begin(at: inGrid(value.startLocation, grid), grid: grid)
                }
                // A click is not a drag: nothing moves or stretches until the pointer has really travelled.
                if abs(value.translation.width) > 3 || abs(value.translation.height) > 3 { didMove = true }
                if didMove { update(to: inGrid(value.location, grid), grid: grid) }
            }
            .onEnded { _ in
                // A click on a note that was not dragged takes it away.
                if !didMove, let id = clickedNote { model.removeMelodyNote(id) }
                drag = nil; gestureBegan = false; clickedNote = nil
            }
    }

    private func begin(at point: CGPoint, grid: PianoRollGrid) {
        focused = true
        clickedNote = nil
        guard let track = model.currentMelodyTrack else { return }
        if let found = grid.hit(x: point.x, y: point.y, in: track.notes) {
            model.selectedMelodyNote = found.id
            clickedNote = found.id
            guard let note = track.notes.first(where: { $0.id == found.id }) else { return }
            drag = found.zone == .end ? .stretch(id: found.id) : .move(id: found.id, grabbedAt: grid.step(atX: point.x) - note.start)
            return
        }
        let id = model.melodyPattern.addNote(track: trackIndex, pitch: grid.pitch(atY: point.y), start: floor(grid.step(atX: point.x)), length: lastLength)
        model.selectedMelodyNote = id
        if let id { drag = .stretch(id: id) }
    }

    private func update(to point: CGPoint, grid: PianoRollGrid) {
        switch drag {
        case .move(let id, let grabbedAt):
            model.melodyPattern.moveNote(track: trackIndex, id: id, pitch: grid.pitch(atY: point.y),
                                         start: max(0, PianoRollGrid.snapped(grid.step(atX: point.x) - grabbedAt)))
        case .stretch(let id):
            guard let note = model.currentMelodyTrack?.notes.first(where: { $0.id == id }) else { return }
            let length = PianoRollGrid.snappedLength(grid.step(atX: point.x) - note.start)
            lastLength = length
            model.melodyPattern.resizeNote(track: trackIndex, id: id, length: length)
        case nil: break
        }
    }
}
