# Auto update improvements

When starting the app, it should automatically check for available updates.
I want to be able to click Update and have the release be downloaded from GitHub automatically.
It should be moved to the Applications folder automatically too.

- [x] Check for updates every time the app starts.
- [x] Download, verify and install the GitHub release in Applications when Update is clicked, then offer to restart.

## Implementation context

Startup checks bypass the daily schedule in `UpdateSchedule.shouldCheck`, while
checks during the same session remain daily. Skipped releases still stay skipped
until a manual check. `ReleaseUpdateTests` covers both schedule paths. Unbundled
development builds and snapshot launches remain offline.

`ReleaseChecker` accepts only the workflow's exact ZIP and SHA-256 asset names
and their URLs in this repository and release. `ReleaseDownloader` streams the
archive hash. HTTPS GitHub release details and its checksum provide the download
trust; the workflow's ad-hoc signature checks integrity, not publisher identity.
The checksum is checked before `ReleaseArchive` opens the ZIP.

`ReleaseArchive` checks central and local filenames, safe paths, aliases, file
types and extras before extraction. Current ditto packages use only 0x5855 Unix
timestamps (8-byte central / 12-byte local); alternate path/link fields are
refused. Local records must be contiguous in central-directory order, with ditto's
signed 16-byte data descriptors; unlisted records and gaps are refused. This
layout was verified against a real `scripts/bundle.sh` ZIP. ZIP64, archives or
expanded payloads of 4 GB or more, and symbolic links
are refused. Revisit these limits if release packaging begins using frameworks
with links or larger models. `ReleaseInstallTests` uses real ditto archives and
ad-hoc signed scratch bundles and rejects traversal, duplicate paths, conflicting
local names, symbolic links and alternate-name/link metadata.

`ReleaseInstaller` stages beside Applications, verifies the bundle identifier,
executable, exact version/build and deep strict signature, then replaces using
Foundation's retained UUID backup. Verification after replacement precedes
backup deletion; failures restore the backup. It refuses to replace an unrelated
bundle. If `/Applications` is unwritable, it uses the user's Applications folder
and shows that location. No library or audio files are involved.

`AppModel+UpdateInstall.swift` downloads and installs off the main actor. Restart
uses normal app termination (including pending-write flushing); a helper waits
for process exit before opening the installed bundle. Development snapshots use
only local release details and do not download or install anything.

Validation also packages a real `scripts/bundle.sh` build (models omitted) using
the workflow's ditto flags, then runs `ReleaseInstallTests` with
`CLAP_UPDATE_TEST_ARCHIVE` and `CLAP_UPDATE_TEST_TAG` to install it into scratch
Applications. The updater and restart alert snapshots are offline fixtures.
Live GitHub transfer, macOS Gatekeeper and actual app relaunch were not exercised
end to end; no live app installation was performed.

Final checks: debug build passed with only the existing Command Line Tools
linker search-path warnings; the full suite passed 413 tests in 89 suites.
The updater tests also passed with the real release archive provided (22 tests
in three suites). Both Update and Restart native alerts were captured and
visually checked. The unbundled Restart snapshot uses the explicit visible
window, as the existing Update fixture does; production waits for an active
main/key window with no chooser or attached sheet.
