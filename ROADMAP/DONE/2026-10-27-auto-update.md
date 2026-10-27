# Auto update

The auto update works well, however the download can take some time and I want the user to see a progress bar or a loading spinner of some sort so they know something is happening in the background.

- [x] Show download and installation activity while keeping the library usable.

## Implementation context

The existing installer wrote to the shared `statusMessage`, but the status bar
only displayed that message during indexing. Update activity now has its own
`AppModel.updateInstallMessage` and native small `ProgressView` above the status
bar, leaving indexing feedback visible. The spinner stays indeterminate because
the existing downloader does not report bytes and verification and installation
have no known duration. It disappears before waiting to offer a restart and on
failure. Downloading and installation still run off the main actor.

`scripts/snapshot.sh --update-download` and `--update-install` set local debug
activity fixtures without network requests or changes to the installed app.
The update prompts retain their existing snapshot options.

Apple's progress indicator guidance informed the native spinner, short task
description, consistent bottom placement, and removal after completion.
`ProgressView` is available from macOS 11, so no macOS 14 fallback is needed.
Apple’s developer release listing showed macOS 27.2 without a beta label; its
public consumer availability was not separately verified. Local runtime checks
use macOS 26.7.2. macOS 14 and 27 runtime verification are unavailable here.

Validation: `scripts/build.sh` passes with the existing Command Line Tools linker
search-path warnings and no new warnings. Download activity in light appearance
and installation activity in dark appearance were rendered and inspected with
scratch data; the dark snapshot also enabled Reduce Motion, Reduce Transparency,
and Increase Contrast. This UI-only slice does not change `ClapCore` behaviour.
The full `scripts/test.sh` suite passes (421 tests in 91 suites).
A live GitHub download and replacement of the installed app were not performed.

Guidance: [progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators),
[designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos),
and [ProgressView](https://developer.apple.com/documentation/swiftui/progressview).
