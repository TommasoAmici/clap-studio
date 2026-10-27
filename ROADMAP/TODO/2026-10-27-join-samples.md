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
