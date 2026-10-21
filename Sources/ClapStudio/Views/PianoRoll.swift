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
            let steps = model.melodyPattern.stepCount
            let grid = PianoRollGrid(stepWidth: max(Self.minStepWidth, (geo.size.width - Self.keyboardWidth) / Double(steps)),
                                     rowHeight: Self.rowHeight)
            // The keyboard sits inside the vertical scroll beside the grid, so the two always line up. Only the grid
            // scrolls sideways, which is needed just for melodies longer than a few bars.
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        keyboard(grid).frame(width: Self.keyboardWidth, height: grid.height)
                        ScrollView(.horizontal) { gridView(grid, steps: steps) }.frame(height: grid.height)
                    }
                    .overlay(alignment: .topLeading) { rowAnchors(grid) }
                }
                .onAppear { reveal(proxy, grid) }
                .onChange(of: trackIndex) { reveal(proxy, grid) }
            }
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

    private func gridView(_ grid: PianoRollGrid, steps: Int) -> some View {
        let pattern = model.melodyPattern
        let track = pattern.tracks.indices.contains(trackIndex) ? pattern.tracks[trackIndex] : nil
        let selected = model.selectedMelodyNote, playhead = model.melodyStep
        let colour = melodyTrackColors[trackIndex % melodyTrackColors.count]
        return Canvas { context, size in
            for pitch in 0..<PianoRollGrid.rows {
                let row = CGRect(x: 0, y: grid.y(ofPitch: pitch), width: size.width, height: grid.rowHeight)
                if NoteNames.isBlackKey(pitch) { context.fill(Path(row), with: .color(.black.opacity(0.14))) }
                if pitch % 12 == 0 { context.fill(Path(CGRect(x: 0, y: row.maxY - 0.5, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.5))) }
            }
            for step in 0...steps {
                let strength = step % 16 == 0 ? 0.55 : step % 4 == 0 ? 0.3 : 0.12
                let x = grid.x(ofStep: Double(step))
                context.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(.secondary.opacity(strength)))
            }
            // The other tracks, faintly, to write against.
            for (index, other) in pattern.tracks.enumerated() where index != trackIndex {
                for note in other.notes { fill(note, grid: grid, in: &context, colour: melodyTrackColors[index % melodyTrackColors.count].opacity(0.28)) }
            }
            for note in track?.notes ?? [] {
                fill(note, grid: grid, in: &context, colour: colour.opacity(0.35 + 0.65 * Double(note.velocity)))
                if note.id == selected {
                    let f = grid.frame(of: note)
                    context.stroke(Path(roundedRect: CGRect(x: f.x, y: f.y, width: f.width, height: f.height), cornerRadius: 2),
                                   with: .color(.white), lineWidth: 1.5)
                }
            }
            if let playhead {
                context.fill(Path(CGRect(x: grid.x(ofStep: Double(playhead)), y: 0, width: 1.5, height: size.height)), with: .color(.white.opacity(0.85)))
            }
        }
        .frame(width: grid.x(ofStep: Double(steps)), height: grid.height)
        .contentShape(Rectangle())
        .gesture(drawing(grid))
    }

    private func fill(_ note: MelodyNote, grid: PianoRollGrid, in context: inout GraphicsContext, colour: Color) {
        let f = grid.frame(of: note)
        context.fill(Path(roundedRect: CGRect(x: f.x, y: f.y + 0.5, width: max(2, f.width - 0.5), height: f.height - 1), cornerRadius: 2), with: .color(colour))
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

    private func drawing(_ grid: PianoRollGrid) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil && !gestureBegan { gestureBegan = true; didMove = false; begin(at: value.startLocation, grid: grid) }
                // A click is not a drag: nothing moves or stretches until the pointer has really travelled.
                if abs(value.translation.width) > 3 || abs(value.translation.height) > 3 { didMove = true }
                if didMove { update(to: value.location, grid: grid) }
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
