# Piano roll

Please remove the slider at the bottom that indicates the scrolling position.

- [x] Remove the horizontal position slider while keeping sideways scrolling and playback follow.

## Implementation context

`Sources/ClapStudio/Views/PianoRoll.swift` no longer adds a position slider
beneath long melodies. The native vertical scroll view now fills the roll's
height. Its `SidewaysScroll` background still handles trackpad swipes and
Shift with the mouse wheel; `PlayheadLine` in `PianoRollBar.swift` still advances
the visible bars during playback. No core logic or new APIs were needed.

The [Melody feature](../../README.md) describes the remaining navigation.

Validated with `scripts/build.sh` and the full `scripts/test.sh` suite
(436 tests across 93 suites). The only build warnings are the existing Command
Line Tools linker search paths; this change introduces no Swift warnings.
`scripts/snapshot.sh --media --melody --melody-bars 8 --select --width 1100`
was inspected in light and dark appearances on macOS 26.7.2 using a synthetic
scratch library and a separate executable name to isolate UI preferences.
The grid fills the available height and retains clipped notes at its right edge,
indicating additional content. The macOS 14 runtime was not available; no new
APIs or availability branches were introduced.

Apple's scroll-view guidance informed retaining standard scrolling gestures and
limited playhead following. The position slider is removed as requested rather
than replaced by another control.
