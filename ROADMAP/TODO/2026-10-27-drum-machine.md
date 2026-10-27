# Drum machine

I don't like the new label we added above each track in the drum machine that says "Bar N". I liked how compact the view was before. Let's get rid of this extra label.

I also don't like the slider we added to show that the area can scroll. Please find a more visually pleasing and native way to communicate to the user that. Take inspiration from the Ableton Live (https://www.ableton.com/en/live/what-is-live/) UI.

Make sure that the `Length [ n  ] bars` input:
- is a number input that the user can increase/decrease with a click or arrow keys: currently you can only type a value
- when changing from singular to plural the UI doesn't shift: `Length [1] bar` vs `Length [2] bars`

## Checklist

- [x] Restore compact rows and replace the scrolling slider with a native scrollbar.
- [x] Add click and arrow-key length adjustment without moving the bar/bars label.

## Implementation context

- `DrumStepGrid.swift` removes the repeated bar heading and its 17-point row
  allowance. Numbered accessibility labels remain on each step.
- Ableton's referenced Arrangement View uses a compact proportional scroll
  thumb. `DrumScroller` uses AppKit's overlay `NSScroller` for the same clear
  indication of visible extent with native appearance, dragging and page clicks.
  It shares the existing offset with all rows; horizontal gestures, resizing
  and playback following still use the virtualized bar viewport.
- See the Drum machine entry in [README](../../README.md) for the controls.
- First-slice verification: build adds no warnings beyond the existing CLT
  linker search paths; the full Swift Testing suite passes. Scratch-library
  snapshots show the native thumb in light (1600-point window, first bar) and
  dark (1250-point minimum, bar-three target) appearances. Both retain the
  fixed sound and mixer controls without repeated headings.
- `DrumLengthControl.swift` keeps the editable count and an `NSStepper`
  together. Its text-field delegate handles Up/Down in AppKit's field editor;
  invalid text restores the current count on commit, and every accepted value
  uses the existing 1…100,000-bar bounds before adjustment to avoid overflow.
  Typing changes the length when committed; stepper clicks and arrows apply
  immediately. The stepper follows a valid typed count before it is committed.
- `DrumPanel.lengthControl` reserves 26 points for the singular/plural suffix.
  At the minimum window width, one-bar and two-bar light snapshots retain the
  exact header positions; the native number field and arrows also fit in dark
  appearance. The field keeps the existing shortening/removal warning.
- AppKit harnesses loaded the actual control/delegate source and exercised
  native target/actions for stepper clicks, Up/Down, typing, invalid input,
  bounds including `Int.max`, scrollbar thumb positions, page/line movement
  and scroll bounds. These checks complement the real-window snapshots;
  the change adds no core behavior requiring a new ClapCore test.
- Final build adds no new warnings; all 413 tests in 89 suites pass after
  the length-control slice. These changes touch only presentation and controls:
  no file writes, schema/model changes or re-embedding are involved.
