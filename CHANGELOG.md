# Changelog

Changes for musicians using Clap Studio. Versions group changes made between
version bumps; earlier GitHub releases may include several builds of one version.

## Unreleased

## 0.29.0

- Publish app updates only when the version increases, avoiding repeat releases
  for ordinary changes to the repository.
- See a spinner and task description while an app update downloads and installs.
- Read release notes in the update dialog and a changelog with each version’s changes.
- Open a VST3 effect’s own editor, keeping presets and hidden settings for
  preview and bounce. Effects without a Mac editor keep parameter sliders.
- Plug-in crashes and hangs are contained in a separate process, with loading
  time limits and cancellation that closes the helper.
- The empty Effects panel is centered, and preview controls stay still while
  samples play.

## 0.28.0

- Build a chain of VST3 effects and preview or bounce copies of selected samples.
  Bypass, reorder, remove effects, and adjust their parameters.
- Keep trims and sound edits when bouncing, include effect tails, and protect
  original samples from being overwritten.
- Load effects that query inactive audio buses correctly.

## 0.27.0

- Native macOS glass controls and toolbar styling follow the system appearance.
- In-app updates can reopen without an extra quarantine warning after verification.

## 0.26.0

- More app actions are available in native macOS menus.
- Native controls, clearer labels, and better sheet and cue editing interactions.
- The drum machine header keeps playback, pattern, and sound controls together.

## 0.25.0

- More compact drum rows leave room for the pattern.
- Drum pattern length can be typed directly.
- Website screenshots refresh correctly after updates.

## 0.24.0

- Download and install app updates directly, then restart when ready.
- Check for updates on launch, even if a recent check already ran.
- Drum pattern bars scroll, and the active bar stays visible.
- Sound variation controls are easier to find and use.

## 0.23.0

- A website introduces the app with light and dark screenshots, playback previews,
  and examples of working with Squid Salmple banks and Pool folders.
- Check for new releases automatically or from the app menu.
- Storage, search, analysis, and map selection are checked with 100,000 samples.
- Drum patterns support multiple bars and MIDI imports with several tracks.
- Keep regular samples out of field-recording segmentation, with undo support.
- Remove a sound from the melody by closing its tab.

## 0.22.0

- Longer MIDI melodies retain all notes and their original tempo.
- Scroll through long melodies in the piano roll.
- Click piano keys to audition pitches, drop a sound onto a melody track, and
  click an existing note to remove it.

## 0.21.0

- Play tuned sample melodies in a piano roll, alongside the drum machine.
- Import MIDI files, add sounds to melody tracks, and remember the melody.
- Duplicate review groups exact copies rather than merely similar sounds.

## 0.20.0

- Browse Squid Pool folders and choose the destination folder when sending sounds.
- Create Pool folders and move unwanted Pool files to the Trash.

## 0.19.0

- Inspect multiple samples together and change their tempo, category, tags,
  or sound edits in one undo step.
- Extend a table selection upwards with Shift.
- The empty kit builder uses the available space.

## 0.18.0

- Native toolbar controls adapt more reliably to the window layout.

## 0.17.0

- Keep toolbar controls visible in narrow windows and when the inspector closes.
- Search stays beside the inspector; view tabs stay beside the sidebar.

## 0.16.0

- Reverse, adjust gain, or filter sounds without changing original files.
- Read and save file metadata.
- Explore recording locations on the Places map.
- Find similar sounds using the microphone or adjust a search with words.
- Swap and shuffle drum sounds.
- Drum steps and toolbar controls stay aligned.

## 0.15.0

- Normalize samples on a Squid drive.
- Preview a sound while selecting multiple samples, and see selection counts.
- Switching to Library or Map leaves the Squid drive view.

## 0.14.0

- Match sample levels when sending them to Squid Salmple.

## 0.13.0

- Squid operations keep the current view open.

## 0.12.0

- Browse Squid banks directly in the sidebar.

## 0.11.0

- Remember the last Squid destination.

## 0.10.0

- Keep categories inside exported WAV files.
- The Squid set header stays visible while browsing.
- Recording locations have a clearer section; empty bird results stay hidden.

## 0.9.0

- Faster library filtering with large sample collections.

## 0.8.0

- Field recording analysis respects a category you set yourself.

## 0.7.0

- Detect Squid Salmple module drives and manage banks and sets.
- See how many free slots a bank has.
- Drum and Squid operations explain when a sample is missing.

## 0.6.0

- Drum parts work with every kind of sound.

## 0.5.0

- Create custom moods for browsing sounds.
- Drag within the waveform and use Command-F to search.
- Clearer inspector and toolbar placement.

## 0.4.0

- Choose library columns and set categories on several samples together.
- A dark Dock icon follows the system appearance.
- Pick recording locations on a map and listen again for birds after changing them.
- More percussion categories, including rimshot and cowbell.
- Bird identification models are included in the app download.

## 0.3.0

- Identify bird species in field recordings and show their timestamps.
- Use the recording location to rule out birds that do not live there.

## 0.2.0

- Analyze long field recordings in segments, name the sounds they contain,
  and search for the matching moment.
- More consistent sound analysis across short and long samples.
- Export training data for a custom sound classifier.

## Initial builds

- Index sample folders in place and keep analysis in a persistent library.
- Browse sounds in a table or a sound map with clusters, lasso selection,
  filters, and adjustable similarity aspects.
- Find sounds with text, an example sound, sound properties, or moods.
- Preview samples, match playback levels, and fit sounds to a project tempo and key.
- Read, audition, edit, and save cue points; trim and export copies.
- Tag sounds, build collections, review duplicates, and undo library edits.
- Build suggested kits and drum patterns with swing, grooves, and saved sounds.
- Browse Squid Salmple USB sticks and send samples to banks or the Pool.
- Watch sample folders for changes and keep analysis between launches.
