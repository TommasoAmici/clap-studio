# Clap Studio

A macOS (SwiftUI + Metal) app to organise and search audio samples for music production.
Point it at a folder; it indexes the files **in place** (nothing is moved, renamed or changed).

- **Similarity search**: select a sample and see the closest-sounding ones (a hi-hat finds other hi-hats).
- **Explore map**: every sample as a dot, laid out by similarity and coloured by cluster. Hover a dot to hear it, click to select, drag it out into Ableton. Pan with a drag or trackpad scroll, zoom with pinch or mouse wheel, double-click empty space to refit.
- **Shuffle** (⌘R, Library tab): puts the list in a random order so browsing doesn't always start with the same samples. Press again for another order; sorting by a column, or ✕ next to the button, goes back. (Rescan Library is ⇧⌘R.)
- **Preview**: select a row (or press space) to hear it; clicking the waveform plays from that point.
- **Drag and drop** any sample (table row, map dot, inspector handle, similar-sounds list) into Ableton or any DAW. Each drag is counted; the "Uses" column and the *Most used* / *Never used* / *Recently grabbed* filters show which samples you keep reusing.
- **Cue points**: read from WAV/AIFF files, edit in the app (click the waveform to audition from a spot, `M` sets a cue exactly there, option-click, drag flags, 1-9 to jump, undo/redo). Edits are saved automatically: the app's database is updated at once and, a moment later, WAV files get the cues embedded (only the cue chunks change; the write is verified and atomic) so other software sees them. Other formats keep their cues in the app only.
- **Sound properties**: loudness, brightness, tempo (loops), pitch or key, and loop vs one-shot are measured at indexing time. They show as sortable columns and filter from the bar above the list and map; the tempo can be corrected in the inspector.
- **Categories**: with CLAP, every sample is sorted into one of 20 categories (kick, snare, pad, vocal, ...) by comparing it to text descriptions. They appear in the sidebar and can be overridden per sample.
- **Moods**: nine moods (Aggressive, Rebellious, Powerful, Epic, Dark, Dreamy, Happy, Uplifting, Groovy) are scored with CLAP the same way, but a sound can have several, and each mood is judged against your own library (a sound gets a mood when it stands out for it). They appear in the sidebar, a Mood column and the filter bar, where moods can be combined. They are recomputed when the library changes; most one-shots have no mood.
- **Duplicates**: the sidebar's duplicates button finds identical files and near-identical sounds, keeps the best copy and hides the rest (reversible from the *Hidden* filter; files are never deleted).
- **Favorites and collections**: star samples (`F`) and group them into collections. *Copy To…* (library or map selection) copies several samples to a folder.
- **Sweep**: with a sample selected, `←` and `→` step through its closest sounds, previewing each. Drop any audio file on the window to find library sounds like it.
- **Ideas**: the lightbulb lists never-used sounds that sit next to the samples you grab most.
- **Project tempo and key**: set them in the toolbar; loops then preview time-stretched to the tempo and tonal sounds transposed to the key (previews only; dragged files are untouched).
- **Map colour, axes and lasso**: colour dots by category, loop/one-shot, usage, tempo, loudness or brightness; lay the map out by any two measured properties instead of similarity; shift-drag a lasso to send the picked dots to a collection, favorites, a tag or Hidden.
- **Similarity aspects**: the sliders under *What counts as similar* weigh overall sound against brightness, pitch (same note), level/punch and length; the list, map highlight and `←` `→` sweep follow.
- **Kit builder**: *Build Kit* suggests a snare, clap, hats and more around a chosen kick, by character, level and pack, with alternatives per slot.
- **Drum machine**: a 16-step, 8-track sequencer (toolbar grid button) for trying sounds together at the project tempo. *Try in Drum Machine* in the kit builder loads each pick with a starter rhythm for its category, and ◀ ▶ swaps in the alternatives. *Add to Drum Machine* is in the library context menu. Mute, solo, volume and swing per pattern; tempo changes apply live.
- **Trim**: set where a sample starts and ends (inspector, or drag the green edges on the waveform) with a short or longer fade-out. The file is never changed: the trim is stored in the index and used for previews, the drum machine and exports. *Export Trimmed Copy…* (or *Copy To…* with a format chosen) writes the trimmed part as WAV, optionally as 16/24-bit, mono and 44.1/48 kHz for samplers. Waveforms and trimming cover the whole file, however long.
- **Squid Salmple** (Settings, off by default): connected USB drives appear in the sidebar with the sets, banks and Pool of the [ALM022 module](https://busycircuits.com/pages/alm022). Banks show their eight channels to hear, drag out or try in the drum machine. *Send to Squid…* (library menu, drum machine, library menu, or the drive) writes up to eight samples as a bank (`Bank N/1…8/Name.wav`, `info.txt`, optionally in a `Set NAME` folder) or any number into the Pool, converted to 16-bit 44.1 kHz mono and cut at 11 s. Existing banks are never overwritten silently. Samples on a stick are analysed but kept out of the library, the map and the saved index, and are never written to.
- **Tags and export names**: free-text tags (searchable, in the sidebar); *Copy To…* names files from a template such as `{category} - {name} - {bpm}`.
- **Everyday**: multi-select with batch actions, undo for hide/favorite/tag/collection edits (option-command-Z), folders are watched and rescanned automatically, and previews can be level-matched.

## Persistence

All expensive results are stored in `~/Library/Application Support/ClapStudio/library.sqlite` (override with `CLAP_DATA_DIR`): file index, embeddings, PCA, clusters, map coordinates, usage and cues. Relaunching loads them straight from disk; only new or changed files are processed, in batches, so an interrupted index resumes. Moved or renamed files are matched by a content fingerprint and keep their embedding, usage and cues.

## Build and run

Needs macOS 14+ and the Swift toolchain (Command Line Tools are enough; Xcode is not required).

```sh
scripts/bundle.sh          # builds build/ClapStudio.app (ad-hoc signed, not sandboxed)
open build/ClapStudio.app
scripts/test.sh            # unit + end-to-end tests
swift run -c release ClapBench 50000 2048   # scale benchmark
```

`scripts/env.sh` builds against the macOS 26 SDK when Xcode is absent, because the default macOS 27 SDK needs a SwiftUI macro plugin that only ships with Xcode. For a quick demo library, run `build/ClapStudio.app/Contents/MacOS/ClapStudio --add-folder /path/to/samples`.

## Similarity model

Three embedders sit behind one protocol:

1. **LAION-CLAP on Core ML** (preferred; HTSAT audio tower, 512-d, trained on audio/text pairs). Create it once with `tools/export_clap.py` (the docstring has the `uv` commands). It also exports the text tower and tokenizer files, which makes the one search box semantic: type "punchy 808 kick" or "warm analog pad" and you get files with that name first, then the sounds that best match the description.
2. **PANNs CNN14 on Core ML** (AudioSet classifier trunk, 2048-d). Create it with `tools/export_model.py`. Used when CLAP is absent.
3. **Built-in DSP features** (log-mel band statistics, envelope, centroid). Used automatically when no model is exported; the status bar says so. Good for coarse grouping, noticeably weaker than the neural models.

Models are compiled by the app on first launch. Switching model re-embeds the library once. `tools/make_references.py` regenerates the librosa / Hugging Face ground truth the tests compare the Swift front ends, tokenizer and Core ML outputs against.

Pipeline (CLAP: 10 s window at 48 kHz, repeat-padded; CNN14: 4 s at 32 kHz): log-mel (vDSP), model, PCA to 128 dims, cosine search (BLAS), spherical k-means for colours, UMAP-style layout for the map.

At 50k samples x 2048 dims (M4 Pro): PCA 2.5 s, layout about 1 s, similarity query under 1 ms.

## Layout

- `Sources/ClapCore`: scanner, storage, audio, ML, indexing, PCA/k-means/layout, cues, playback (no UI).
- `Sources/ClapStudio`: SwiftUI app and Metal map.
- `Sources/ClapBench`: benchmark. `Tests/ClapCoreTests`: Swift Testing suites. `tools/`: model export.
