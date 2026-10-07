# Clap Studio

A macOS (SwiftUI + Metal) app to organise and search audio samples for music production.
Point it at a folder; it indexes the files **in place** (nothing is moved, renamed or changed).

- **Similarity search**: select a sample and see the closest-sounding ones (a hi-hat finds other hi-hats).
- **Explore map**: every sample as a dot, laid out by similarity and coloured by cluster. Hover a dot to hear it, click to select, drag it out into Ableton. Pan with a drag or trackpad scroll, zoom with pinch or mouse wheel, double-click empty space to refit.
- **Preview**: select a row (or press space) to hear it; clicking the waveform plays from that point.
- **Drag and drop** any sample (table row, map dot, inspector handle, similar-sounds list) into Ableton or any DAW. Each drag is counted; the "Uses" column and the *Most used* / *Never used* / *Recently grabbed* filters show which samples you keep reusing.
- **Cue points**: read from WAV/AIFF files, edit in the app (add with `M` or option-click, drag flags, 1-9 to jump, undo/redo). They live in the app's database; *Write to File…* (WAV only, confirmed, optional `.bak`) embeds them so other software sees them.

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

Two embedders sit behind one protocol:

1. **PANNs CNN14 on Core ML** (AudioSet-trained, knows kicks, hats, snares, ...). Create it once with `tools/export_model.py` (the docstring has the `uv` commands: a Python 3.12 venv with `torch` and `coremltools`; downloads the CC BY 4.0 weights from Zenodo, converts, and verifies against PyTorch before saving to `~/Library/Application Support/ClapStudio/Models/`). The app compiles it on first launch and re-embeds the library once.
2. **Built-in DSP features** (log-mel band statistics, envelope, centroid). Used automatically when the model is absent; the status bar says so. Good for coarse grouping, noticeably weaker than the neural model.

Pipeline: 4 s window, 32 kHz mono, PANNs-compatible log-mel (vDSP), model trunk, max+mean pooling over only the real (non-padded) frames, PCA to 128 dims, cosine search (BLAS), spherical k-means for colours, UMAP-style layout for the map.

At 50k samples x 2048 dims (M4 Pro): PCA 2.5 s, layout about 1 s, similarity query under 1 ms.

## Layout

- `Sources/ClapCore`: scanner, storage, audio, ML, indexing, PCA/k-means/layout, cues, playback (no UI).
- `Sources/ClapStudio`: SwiftUI app and Metal map.
- `Sources/ClapBench`: benchmark. `Tests/ClapCoreTests`: Swift Testing suites. `tools/`: model export.
