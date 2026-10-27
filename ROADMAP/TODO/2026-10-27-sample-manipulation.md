# Sample manipulation

Currently, there are very limited options to manipulate samples. I want to add VST support so we can load plugins and add distortion, reverb, etc.

The plugins should be read from the default locations like Ableton does. Let's start with VST3 only for now.

After having applied a VST to a sample, the user should be able to bounce the sample with the effects applied and save them.
Show them a native file save dialog so they can choose a folder and file name.

I'd also like to be able to apply the same effect chain to multiple samples and save them all at once. Similar to how photos can be processed in Adobe Lightroom applying the same corrections and effects at scale.

## Checklist

- [x] Discover installed VST3 bundles in the standard user and system folders.
- [x] Load effects, edit their parameters and render an ordered chain.
- [x] Audition and bounce one sample with a native save dialog.
- [x] Bounce selected samples through the same chain into a chosen folder.

## Implementation context

- `VST3Discovery` searches user and system `Library/Audio/Plug-Ins/VST3`
  folders, including vendor subfolders, without executing plugin code or
  descending into bundle contents. Missing folders are harmless.
- `VST3DiscoveryTests` covers nested vendor folders, duplicate roots and
  absent locations. Loading happens only when an effect is added.

- `CVST3` bridges the official MIT VST3 interfaces, pinned at
  `4f547e8e102b47de4a8b8aaf343c73b700786372`; the notice is bundled with
  the app. Component/controller lifecycle, parameters and setup run on the
  main actor. Decode/process/write run in cancellable detached tasks.
- `EffectBounce` starts fresh instances for each sample, applies existing
  trim and sound edits first, and writes verified atomic stereo float WAV
  copies. Latency is removed; reported tails are capped at ten seconds per
  effect, with a configurable extra tail for effects reporting none.
  Sources (including other library originals and hard links) are protected.
- Official SDK `adelay.vst3` was built outside the repository and its SDK
  validator passed 57 tests. Set `CLAP_VST3_TEST_PLUGIN` to that bundle to
  exercise `VST3RenderTests`, which checks an audible 50 ms delay, bypass
  and fresh-instance repeatability. No user-installed plugin was available.
- Full tests use `scripts/test.sh --no-parallel`: concurrent existing
  playback tests crashed in CoreAudio with "player did not see an IO cycle".
  The final serial suite passed all 421 tests, including the official plugin
  fixture when its environment variable is set. The host adds no new
  compiler warnings; CLT linker search-path warnings already existed.
- The first host supports offline stereo effects and generic normalized
  parameters, not instruments, custom plugin editors, MIDI or presets.
  Optional sidechains are deactivated; effects must accept this layout.
  Plugin code runs in the app process. Very long files are decoded whole,
  matching the existing trim renderer; cancellation waits for that read.

- `EffectsWorkbench` owns a native floating `NSPanel` with the shared session
  recipe, selected-sample snapshot, rendered preview and file choosers.
  `AppModel+Effects` connects menu/inspector actions and routes errors and
  status through `AppModel`. Generic controls use normalized percentages;
  a custom plugin editor and persisted recipes are deferred. The chain is
  deliberately separate from undoable library edits: see [README](../../README.md).
- A panel fits Apple's HIG guidance for repeated input and observing results;
  it is resizable, floats within the app and hides when the app deactivates.
  Save and folder selection use `NSSavePanel` and `NSOpenPanel`. Opening a
  different selection cancels prior work and dismisses a pending chooser.
  Parameter/preview changes cancel stale rendering. Cancel keeps completed
  outputs and reports progress; displayed batch failure details are capped.
- `scripts/snapshot.sh --effects --effects-plugin /path/adelay.vst3` renders
  the actual panel using a scratch library. Light appearance at 640 points
  and dark at the 520-point minimum were inspected on macOS 26.6.2.
  The deployment target remains macOS 14; older-OS runtime and current
  stable macOS 27 runtime were unavailable. No custom newer OS API is used.
- `--effects-save` exercises the native Save sheet without saving a file.
  Its remote system view is blank in bitmap caching, a limitation of the
  snapshot path rather than evidence of a broken file chooser. Native
  capture succeeded with existing screen-capture access; the native Save
  filename, folder chooser and Cancel/Save actions were inspected. File
  chooser completion was not automated; write safety and actual processed WAV output are
  covered by the core tests.
