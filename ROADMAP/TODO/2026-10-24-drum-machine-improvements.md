# Drum machine improvements

- [x] If there are more than 1 bar, they should scroll. Get rid of the pagination with arrow buttons `Bar 1 of 2`
- [x] let's get rid of the `Open MIDI...` button, it's a relatively niche feature
- [x] let's move the bar length input and `Clear steps` button so they match the UI of the Melody sequencer. They should be in the same position in both drawers so it's more intuitive for users
- [x] the dropdown `close/medium/wide` is a bit unclear to me, can you make it more intuitive?
- [ ] the dropdown `close/medium/wide` shows an empty selection instead of any of the values it contains
- [x] get rid of the BPM input, the user should just use the global project BPM in the top toolbar

## Implementation context

- `DrumStepGrid.swift` shares one horizontal offset across all tracks, with
  track names and mixer controls kept in place. The viewport renders only the
  bars on screen, so very long imported patterns do not create every step view.
- The existing `SidewaysScroll` handler also used by Melody supplies trackpad
  and Shift-wheel input; a slider provides the same fallback as the piano roll.
  `drumBar` is now a playback/snapshot scroll target, not a page selection.
- See the Drum machine entry in [README](../../README.md) for the controls.
- SwiftUI text at the leading clipped bar disappeared in real-window snapshots,
  including with fixed stack sizes. Bar numbers are drawn in a small Canvas,
  as in the piano roll; numbered step accessibility labels remain on the cells.
- Scrolling verified with four bars at 1600 points wide and a bar-three target
  at the 1250-point window minimum. The whole existing suite passes (399 tests
  in 87 suites). Builds add no warnings beyond the existing CLT linker paths.
- Drum MIDI import stays available through File > Open Drum MIDI File… and
  dropping a MIDI file on the drawer. Only the drawer button was removed.
- The drawer no longer has a second project BPM field. The top toolbar remains
  the tempo control; groove and MIDI tempo changes still set the same project.
- Length and Clear Steps now sit just before Close in the header, matching
  Melody. Groove, Shuffle Kit, swing and preview volume use the next row so
  their controls stay readable at the minimum window width. Clear Steps moved
  out of the status bar; its action and enabled state are unchanged.
- The choice is labelled Sound variety and offers Similar, Balanced and
  Adventurous with a plain-language explanation. The UI maps these onto the
  existing Close/Medium/Wide raw values, keeping saved settings and the
  nearest-4/12/40 candidate pools unchanged. No new core behavior is needed.
