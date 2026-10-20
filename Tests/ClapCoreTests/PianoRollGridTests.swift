import Foundation
import Testing
@testable import ClapCore

@Suite struct PianoRollGridTests {
    private let grid = PianoRollGrid(stepWidth: 20, rowHeight: 10)

    @Test func theHighestNoteIsAtTheTopAndPositionsRoundTrip() {
        #expect(grid.y(ofPitch: 127) == 0 && grid.y(ofPitch: 0) == 1270, "high notes are drawn above low ones")
        #expect(grid.pitch(atY: 0) == 127 && grid.pitch(atY: 9.9) == 127 && grid.pitch(atY: 10) == 126)
        #expect(grid.pitch(atY: -50) == 127 && grid.pitch(atY: 99_999) == 0, "pointing past the keyboard picks the end note")
        for pitch in [0, 36, 60, 127] { #expect(grid.pitch(atY: grid.y(ofPitch: pitch) + 5) == pitch) }
        #expect(grid.step(atX: 50) == 2.5 && grid.x(ofStep: 2.5) == 50)
        #expect(grid.height == 1280)
    }

    @Test func snappingGoesToWholeStepsAndDoesNotGoBelowOne() {
        #expect(PianoRollGrid.snapped(2.4) == 2 && PianoRollGrid.snapped(2.6) == 3)
        #expect(PianoRollGrid.snappedLength(0.2) == 1 && PianoRollGrid.snappedLength(3.4) == 3, "a drawn note is at least a step")
    }

    @Test func aNoteIsDrawnWhereItsTimeAndPitchSay() {
        let frame = grid.frame(of: MelodyNote(pitch: 60, start: 4, length: 2))
        #expect(frame.x == 80 && frame.width == 40 && frame.y == 670 && frame.height == 10)
    }

    @Test func pointingAtANoteFindsItsBodyOrItsEnd() throws {
        let note = MelodyNote(pitch: 60, start: 4, length: 2)          // x 80...120, y 670...680
        let body = try #require(grid.hit(x: 90, y: 675, in: [note]))
        #expect(body.id == note.id && body.zone == .body)
        let end = try #require(grid.hit(x: 117, y: 675, in: [note]))
        #expect(end.zone == .end, "the last few points are the grip for stretching")
        #expect(grid.hit(x: 79, y: 675, in: [note]) == nil && grid.hit(x: 90, y: 665, in: [note]) == nil, "outside is empty space")
    }

    @Test func aShortNoteCanStillBeMovedByItsBody() throws {
        let short = MelodyNote(pitch: 60, start: 0, length: 0.25)      // 5 points wide
        let left = try #require(grid.hit(x: 1, y: 675, in: [short]))
        #expect(left.zone == .body, "half of a narrow note stays body, so it can be grabbed")
        let right = try #require(grid.hit(x: 4, y: 675, in: [short]))
        #expect(right.zone == .end)
    }

    @Test func theNoteOnTopWinsWhereTwoOverlap() throws {
        let under = MelodyNote(pitch: 60, start: 0, length: 4), over = MelodyNote(pitch: 60, start: 2, length: 4)
        let found = try #require(grid.hit(x: 50, y: 675, in: [under, over]))
        #expect(found.id == over.id, "later notes are drawn last, so they are the ones you see")
    }
}
