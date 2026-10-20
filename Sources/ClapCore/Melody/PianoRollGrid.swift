import Foundation

/// The geometry of the piano roll: where a pitch and a time sit on screen, and which note a point is on. The
/// keyboard is drawn with the highest note at the top (y grows downward).
public struct PianoRollGrid: Equatable, Sendable {
    public static let rows = 128

    /// Points per step (a sixteenth note).
    public var stepWidth: Double
    /// Points per semitone.
    public var rowHeight: Double

    public init(stepWidth: Double, rowHeight: Double) { self.stepWidth = stepWidth; self.rowHeight = rowHeight }

    public var height: Double { Double(Self.rows) * rowHeight }

    public func y(ofPitch pitch: Int) -> Double { Double(MelodyNote.pitchRange.upperBound - Self.clamped(pitch)) * rowHeight }

    /// The note whose row holds `y`; above or below the keyboard gives its first or last note.
    public func pitch(atY y: Double) -> Int { Self.clamped(MelodyNote.pitchRange.upperBound - Int((y / rowHeight).rounded(.down))) }

    public func x(ofStep step: Double) -> Double { step * stepWidth }
    public func step(atX x: Double) -> Double { x / stepWidth }

    public func frame(of note: MelodyNote) -> (x: Double, y: Double, width: Double, height: Double) {
        (x(ofStep: note.start), y(ofPitch: note.pitch), note.length * stepWidth, rowHeight)
    }

    /// Positions are drawn on whole steps.
    public static func snapped(_ steps: Double) -> Double { steps.rounded() }
    /// A drawn note is never shorter than one step.
    public static func snappedLength(_ steps: Double) -> Double { max(1, steps.rounded()) }

    public enum Zone: Equatable, Sendable { case body, end }

    /// The note under a point, and whether the point is on its body (to move it) or its right edge (to stretch it).
    /// Later notes are drawn last, so they win. The edge is at most half the note, so a short note can still be grabbed.
    public func hit(x: Double, y: Double, in notes: [MelodyNote], endGrip: Double = 6) -> (id: UUID, zone: Zone)? {
        for note in notes.reversed() {
            let f = frame(of: note)
            guard x >= f.x, x <= f.x + f.width, y >= f.y, y < f.y + f.height else { continue }
            return (note.id, x >= f.x + f.width - min(endGrip, f.width / 2) ? .end : .body)
        }
        return nil
    }

    private static func clamped(_ pitch: Int) -> Int { min(max(pitch, MelodyNote.pitchRange.lowerBound), MelodyNote.pitchRange.upperBound) }
}
