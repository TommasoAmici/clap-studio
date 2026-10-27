# Join samples

One useful feature I want to add is to create a single audio file from multiple samples and then add cue points
to select sub samples. This can be useful to change samples when playing live without loading
a new audio file.

The user would select multiple samples from the Library list or Map.
Using a context menu entry, they would then `Join samples...`.
The resulting audio file should join all the selected samples introducing a short silence
between each source sample.
Each section of the newly created audio file should be correctly chopped with cue start/end
points.

There should be a few options in the `Join samples...` dialog:

- max length: if the selected samples + the silence between them are longer than the max length, multiple files will be created
- length of silence between samples: default 0.25s
- max cue points: if the selected samples are more than the max cue points, multiples
  files will be created. If a sample file already contains cue points, they should be discarded when joining.

The settings can be saved as presets. There should be a default preset for the ALM Salmple with the max length allowed by the module,
the default silence length, and the max cue points allowed by the module.
Check the documentation for the ALM Salmple module: https://busycircuits.com/pages/alm022

When saving, there should be the native folder selection dialog so users can choose where to save the joined
audio files.

## Implementation checklist

- [x] Join edited sounds into verified WAV copies, with silence, named cue regions,
  length and cue-count limits, and source and destination protection.
- [ ] Add the Library and Map action, native folder chooser, editable settings,
  saved presets and the ALM Squid Salmple preset; document and check the dialog.

## Implementation context

- ALM's [product page](https://busycircuits.com/pages/alm022) specifies approximately
  11 seconds at 16-bit/44.1 kHz per channel; its firmware v88 notes increase cue
  sets to 64. The manual, page 13, says ordinary WAV markers become cue sets
  when loading. The preset uses 11 seconds, 64 sounds and 0.25 seconds of silence.
- Each sound gets one named start marker, with its exact length in a standard
  WAV `LIST/adtl/ltxt` region record. Adding separate end markers would make the
  silent gaps selectable cue sets on the module. Exact region-end handling on
  the module remains a hardware validation gap; proprietary metadata is not
  invented. `FileCue` and the existing cue reader keep their existing meaning.
- Joining applies existing trims and sound edits before measuring limits. A
  sound longer than the chosen maximum is refused before anything is saved:
  trim it in the inspector or raise the maximum. Sounds remain intact.
- `JoinPlanner` measures converted frames and inserts silence only between
  sounds in the same output. `JoinExporter` stages all converted sounds and
  outputs beside the destination, verifies WAV format and cue bounds, then
  publishes with new names and rolls back a failed publication. Cancellation
  is checked between reads, conversions and chunk writes. Audio writing uses
  65,536-frame chunks; metadata verification bounds joined files to 300
  seconds. Native source decoding is capped at 64 million frames before
  allocating the whole buffer required by sound edits.
- `JoinTests` and `JoinExportTests` cover length/count boundaries, exact silent
  gaps and region ends, edits, resampling, stereo and mono, cue replacement,
  source bytes, existing names, failed batches and cancellation. Both suites
  were exercised red before implementation and green afterward.
- Core slice validation: `scripts/build.sh` passed with only the existing
  Command Line Tools linker search-path warnings; the complete
  `scripts/test.sh` run passed 447 tests in 95 suites.
