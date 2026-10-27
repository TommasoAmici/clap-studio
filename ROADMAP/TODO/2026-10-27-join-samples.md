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
- [x] Split oversized selected sounds across files, preserving every frame
  without adding silence inside a source.
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
- Joining applies existing trims and sound edits before measuring limits.
  The first core slice grouped whole sounds and refused oversized sources.
  The user subsequently chose splitting: a longer sound now continues across
  files from exact converted source-frame offsets, with no inserted silence
  between its pieces. Sounds that fit the maximum stay together.
- `JoinPlanner` measures converted frames and inserts silence only between
  sounds in the same output. `JoinExporter` stages all converted sounds and
  outputs beside the destination, verifies WAV format and cue bounds, then
  publishes with new names and rolls back a failed publication. Cancellation
  is checked between reads, conversions and chunk writes. Audio writing uses
  65,536-frame chunks; metadata verification bounds joined files to 300
  seconds. `JoinSourceRenderer` streams unedited sources through one continuous
  high-quality converter into temporary CAF files, so a long source does not
  need to fit in memory or a RIFF file. Sound edits require whole buffers and
  are capped at 64 million native, edited and converted frames.
- `JoinTests` and `JoinExportTests` cover length/count boundaries, exact silent
  gaps and region ends, edits, resampling, stereo and mono, cue replacement,
  source bytes, existing names, failed batches and cancellation. Both suites
  were exercised red before implementation and green afterward.
- Core slice validation: `scripts/build.sh` passed with only the existing
  Command Line Tools linker search-path warnings; the complete
  `scripts/test.sh` run passed 447 tests in 95 suites.
- Splitting validation: planner/export tests were red for oversized sources
  before the change, then passed with contiguous source offsets. A 3.1-second
  48 kHz regression crosses multiple 65,536-frame reads and output files;
  its concatenated result matches a continuous high-quality render, including
  trim fades, within one 16-bit rounding step. Stored trims are fitted to the
  actual file duration. All 17 join tests pass; the full suite passed 453
  tests in 95 suites after `scripts/build.sh`, with no new warnings.
