# Clap Studio

A macOS (SwiftUI + Metal) app to organise and search audio samples for music production.
Point it at a folder; it indexes the files **in place** (nothing is moved, renamed or changed).

- **Similarity search**: select a sample and see the closest-sounding ones (a hi-hat finds other hi-hats).
- **Explore map**: every sample as a dot, laid out by similarity and coloured by cluster. Hover a dot to hear it, click to select, drag it out into Ableton. Pan with a drag or trackpad scroll, zoom with pinch or mouse wheel, double-click empty space to refit.
- **Preview**: select a row (or press space) to hear it; clicking the waveform plays from that point.
- **Drag and drop** any sample (table row, map dot, inspector handle, similar-sounds list) into Ableton or any DAW. Each drag is counted; the "Uses" column and the *Most used* / *Never used* / *Recently grabbed* filters show which samples you keep reusing.
- **Cue points**: read from WAV/AIFF files, edit in the app (click the waveform to audition from a spot, `M` sets a cue exactly there, option-click, drag flags, 1-9 to jump, undo/redo). Edits are saved automatically: the app's database is updated at once and, a moment later, WAV files get the cues embedded (only the cue chunks change; the write is verified and atomic) so other software sees them. Other formats keep their cues in the app only.

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

1. **LAION-CLAP on Core ML** (preferred; HTSAT audio tower, 512-d, trained on audio/text pairs). Create it once with `tools/export_clap.py` (the docstring has the `uv` commands). It also exports the text tower and tokenizer files, which enables the **Sound** search scope: type "punchy 808 kick" or "warm analog pad" and samples are ranked by how well they match the description.
2. **PANNs CNN14 on Core ML** (AudioSet classifier trunk, 2048-d). Create it with `tools/export_model.py`. Used when CLAP is absent.
3. **Built-in DSP features** (log-mel band statistics, envelope, centroid). Used automatically when no model is exported; the status bar says so. Good for coarse grouping, noticeably weaker than the neural models.

Models are compiled by the app on first launch. Switching model re-embeds the library once. `tools/make_references.py` regenerates the librosa / Hugging Face ground truth the tests compare the Swift front ends, tokenizer and Core ML outputs against.

Pipeline (CLAP: 10 s window at 48 kHz, repeat-padded; CNN14: 4 s at 32 kHz): log-mel (vDSP), model, PCA to 128 dims, cosine search (BLAS), spherical k-means for colours, UMAP-style layout for the map.

At 50k samples x 2048 dims (M4 Pro): PCA 2.5 s, layout about 1 s, similarity query under 1 ms.

## Layout

- `Sources/ClapCore`: scanner, storage, audio, ML, indexing, PCA/k-means/layout, cues, playback (no UI).
- `Sources/ClapStudio`: SwiftUI app and Metal map.
- `Sources/ClapBench`: benchmark. `Tests/ClapCoreTests`: Swift Testing suites. `tools/`: model export.
