# Auto update

When a new version is released in GitHub releases, I'd like the user to see a pop-up prompting to update.

- [x] Check the current repository for newer releases, prompt to download, and
      provide a manual check, with tests and documentation.

## Implementation context

The existing workflow tags every push as `vVERSION-build.NUMBER` and stamps
`CFBundleVersion` with the GitHub run number. Same-version builds must therefore
be compared as updates rather than treated as prereleases. Plain `vX.Y.Z`
stable tags are also understood, with build zero.

The repository is currently private: unauthenticated `releases/latest` returned
HTTP 404, and the coordinator verified the visibility with authenticated `gh`.
The user chose to keep this repository as the source and plans to make it public.
The app intentionally ships no developer credential. Until visibility changes,
automatic checks stay silent and a manual check reports that no public release
is available; live public notifications cannot yet be verified. This is an
external distribution prerequisite, not a reason to change repository visibility
as part of the implementation.

`Sources/ClapCore/ReleaseUpdate.swift` owns numeric version/build comparison,
GitHub response decoding, HTTP failures, release-page validation and the daily
schedule. Only published stable releases newer than the installed version and
build can be offered. HTTP 404 is a missing public release, not proof that the
installed app is current.

`Sources/ClapStudio/AppModel+Updates.swift` reads the installed version from the
bundle, starts one hourly timer that checks when a day has elapsed, and cancels
a previous request before a manual replacement. `updates.lastCheck` records
attempts so an unavailable server is not polled repeatedly. `updates.skippedTag`
remembers an exact release, including its build; the manual menu ignores it.
The native prompt waits for an active normal window, no app-modal window, and
no attached sheet on its parent. Prefer the main window over the key window:
a chooser itself can become key and have no attached sheet, so both `isSheet`
and `sheetParent` must also rule it out as a prompt parent. The menu stays
disabled until the check or prompt finishes. No download or installation is
automatic. See the README's Updates section for the user flow.

`scripts/snapshot.sh --update` uses a local example release through
`CLAP_SNAPSHOT_UPDATE=1`. The fixture exists only in the debug snapshot code and
never contacts GitHub. Unbundled runs have no installed release metadata, and
ordinary snapshots suppress automatic checks.

The focused `ReleaseUpdateTests` passed after the missing implementations were
confirmed red. The final debug build passed with no new warnings (the Command
Line Tools linker search-path warnings are present on the base commit). The
whole suite passed 394 tests in 85 suites, including the installed model tests.

On macOS 26.6.2, `NSView.cacheDisplay` captured only a blank rounded background
for the native `NSAlert`, even when the alert was retained until dismissal.
The `--update` fixture therefore captures the real window with `screencapture`
after checking that screen capture access is already granted. It never requests
new permission. Other snapshot modes keep their permission-free bitmap renderer.
The final image was read and its title, version/build, explanation and all three
buttons were visible. Reproduce with a scratch `CLAP_DATA_DIR` and
`scripts/snapshot.sh /tmp/clap-update.png --update`.

`scripts/bundle.sh` also passed with an empty scratch `CLAP_MODELS_DIR`; its
`Info.plist` supplied version `0.22.0` and build `1`, and the strict ad-hoc
signature check passed. The model-less bundle was only a packaging check; the
full test suite above used the installed models normally.
