# AGENTS.md

Clap Studio is a macOS 14+ SwiftUI + Metal app for organising audio samples, built as a Swift package with no Xcode
project. `README.md` is the feature reference and user-facing spec: read the section for the feature you touch, and
update it in the same change when behaviour changes.

## Build, test, verify

Always go through `scripts/`, never bare `swift build` / `swift test`: `scripts/env.sh` picks the macOS 26 SDK when
only the Command Line Tools are installed (the default SDK needs a SwiftUI macro plugin that ships with Xcode only), and
`scripts/test.sh` passes the Swift Testing plugin path.

- `scripts/build.sh` compiles (debug). Run it after every change; the work is done when it builds with no new warnings.
- `scripts/test.sh [--filter SuiteName]` runs the tests. Run the whole suite before committing.
- `scripts/snapshot.sh [out.png] [--select|--map|--drums|--width PX|...]` renders the real window to a PNG (options
  are listed at the top of the script). Use it to check every UI change, then read the PNG. Options that edit the
  library change the real one, so point `CLAP_DATA_DIR` at a copy for those.
- `scripts/bundle.sh` builds `build/ClapStudio.app`; it is needed for anything that depends on `Info.plist`
  (microphone permission, icon, bundled models).

Keep `CLAP_DATA_DIR` pointed at a scratch folder when running the app against experimental changes: the default
database at `~/Library/Application Support/ClapStudio/library.sqlite` is the user's real library.

## Layout and boundaries

- `Sources/ClapCore`: all logic (storage, audio, DSP, ML, indexing, export). Imports Foundation, Accelerate,
  AVFoundation, Core ML; never SwiftUI or AppKit. New logic goes here so it can be tested.
- `Sources/ClapStudio`: UI only. `AppModel` is the single `@MainActor @Observable` state object, split by feature into
  `AppModel+Feature.swift` extensions. Views read it with `@Environment(AppModel.self)`.
- `Tests/ClapCoreTests`: Swift Testing (`@Suite`, `@Test`, `#expect`) against `ClapCore` only. `TestSupport` makes temp
  stores and files; `writeTestWav` synthesises audio. `References.swift` holds ground truth produced by
  `tools/make_references.py`.
- `tools/`: Python model export and reference generation. Use the `uv` commands in each script's docstring.

Each file holds one concern. When a file nears 400 lines, split it along a feature seam (as `AppModel+*.swift` and
`LibraryStore+*.swift` do) rather than growing it.

## Invariants

- **The user's audio files are read-only** except for the few explicit writers (`WavCueWriter`,
  `WavMetadataWriter`, `SquidNormalizer`, Squid export). Any write to a user file must be atomic and verified: write a
  clone, check it, then replace. Files on a USB drive outside the Squid features are never written.
- **Non-destructive edits**: trims and sound edits live in the database and are applied at playback/export time.
- **Undo**: every library edit the user makes goes through `LibraryEdit` and the undo stack; a batch action on a
  selection is a single undo step.
- **Schema changes** go in `Schema.swift` as a new `vN` function plus a `currentVersion` bump. Never edit an existing
  migration; libraries in the wild have already run it.
- **Re-embedding is expensive** (minutes to hours for big libraries). Changing `SamplePreprocessor`, the log-mel front
  end or the model version triggers it; call that out explicitly in the commit body.
- **Licensing**: BirdNET code sits behind `#if NON_COMMERCIAL`. Anything bird-species related must compile out cleanly
  with `NON_COMMERCIAL=0 scripts/build.sh`; check both builds when touching it.

## SwiftUI and macOS practices

- State: `@Observable` classes with `@State` ownership at the root and `.environment(...)` injection; `@Bindable` for
  bindings into an observable. Mark non-UI properties on `AppModel` `@ObservationIgnored` (services, tasks, caches) so
  they don't invalidate views.
- Concurrency: the UI and `AppModel` are `@MainActor`. Move heavy work (decoding, DSP, ML, SQLite batch writes,
  filesystem scans) off the main actor with `Task.detached`, then publish results back on the main actor. Pass
  cancellation via `CancelToken` or task cancellation, and cancel the previous task before starting a replacement
  (search-as-you-type, refine, rescan).
- Performance: libraries reach 100k rows. Recompute derived lists in one place (`refilter()`, wrapped in
  `batchFilterChanges` for multi-property changes), keep view bodies free of sorting and filtering, and use revision
  counters (`visibleRevision`, `mapVersion`) for views that cannot diff large arrays. Use vDSP/BLAS for numeric loops.
  Measure scale changes with `scripts/bench.sh`.
- Platform feel: follow the macOS Human Interface Guidelines. Every action reachable from the menu bar or a context
  menu, keyboard shortcuts in `.commands`, native controls (`Table`, `Inspector`, `NavigationSplitView`, toolbar items)
  over custom ones, SF Symbols for icons, and system colours and materials so light and dark mode both work. Drop to
  AppKit (`NSViewRepresentable`) only where SwiftUI lacks the behaviour, as the library table (`LibraryList.swift`) and the Metal map (`MapPanel.swift`) do.
- Availability: the deployment target is macOS 14. Gate newer APIs with `if #available(macOS 15.0, *)` and keep a
  macOS 14 fallback.
- Persistence: library data in SQLite via `LibraryStore`; small UI preferences in `UserDefaults` with a namespaced key
  (`"drum.variation"`, `"squid.matchLevels"`).
- Errors shown to the user go to `AppModel.errorMessage` / `statusMessage` in plain language that says what failed and
  what is safe ("Files are only read, never moved or changed").

## Writing style

- UI text, README and comments use plain, concrete English addressed to a musician, not a developer.
- Doc comments (`///`) explain why or what a value means to the user; one line where possible, matching the existing
  density.
- Tests describe behaviour in their names (`clampingKeepsTheTrimInsideTheFile`) and put the reason in the `#expect`
  message.

## Commits and releases

- Conventional commits, subject at most 25 characters (`feat(inspector): multi sound edit`), with a body of 72-column
  lines saying what changed and why for `feat`, `fix` and `refactor`.
- One logical change per commit; README updates ride along with the feature.
- Every push to `main` triggers `.github/workflows/release.yml`, which publishes a GitHub release. A version bump is a
  separate `chore(release): bump to X.Y.Z` commit that changes `CFBundleShortVersionString` in `scripts/bundle.sh`.
- `ROADMAP/TODO/` holds planned work as checklists; tick items off when they ship.
