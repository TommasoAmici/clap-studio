# Changelog

Please keep a user readable changelog that lists all added features, bug fixes and other things
that might interest users.

When preparing a release, update the changelog (update the bump-version-and-push skill with these
instructions).

When creating a GitHub release, add the release notes for the current version in GitHub.

When showing the update dialog, include the release notes.

- [x] Keep a musician-readable changelog and include it when preparing and publishing releases.
- [x] Show each release’s notes in the update dialog.

## Implementation context

The existing workflow published builds for pushes without a marketing-version
bump, so the notes extractor supports pending changes plus the current version.
The separate release-guard feature limits publication to increased versions.
Release preparation moves pending entries into the new version section while
preserving earlier history.

The initial history is reconstructed from release-bump commits and their changes,
without treating commit dates as publication dates.

`CHANGELOG.md` uses exact `## Unreleased` and `## X.Y.Z` headings.
`scripts/release-notes.py` selects the current version and prefixes pending
entries as “Changes in this build”; missing, empty, or duplicate version
sections stop publication. The workflow adds its installation/licensing notice
after those notes and passes a file to `gh release create`. The release skill
prepares the changelog in a separate documentation commit before the version
bump, preserving the existing dedicated release commit.

Validation for this slice: the extractor was red before implementation and all
three Python behavior tests now pass; the app builds with only the existing
Command Line Tools linker-path warnings, and all 421 Swift tests pass. The
skill validator rejects the pre-existing `disable-model-invocation` field, so
that user-required invocation setting is preserved. No GitHub release was
created as part of local verification.

`ReleaseChecker.update` reads GitHub’s optional `body` into
`ReleaseUpdate.releaseNotes`, trimming only outer whitespace. Missing, null,
and blank notes remain compatible with older releases. The native update
alert uses `UpdateReleaseNotes` as an accessory: an uneditable, selectable
`NSTextView` inside an `NSScrollView` keeps long notes separate from the fixed
action buttons. Heading and bullet markers are styled lightly, inline Markdown
is parsed, and links stay inert. No web view or remote content is loaded.

Apple’s macOS and alert HIG support native accessory views and concise alert
copy. `NSAttributedString` Markdown parsing is available from macOS 12; the
existing macOS 14 target needs no availability branch. Current public release
information was checked on Apple’s security-release page, which lists macOS
27.2; this machine runs 26.7.2 and cannot verify macOS 14 or 27 at runtime.

The new Swift tests first failed because `ReleaseUpdate` lacked notes, then
passed with the implementation. Both tests cover the published text and
compatibility with older releases. `ReleaseUpdateTests` has 11 passing tests;
the full suite has 423 passing tests.

UI validation used scratch data on macOS 26.7.2: the default prompt in light
appearance, long notes in dark appearance with Reduce Motion, Reduce
Transparency and Increase Contrast, and the compact missing-notes label. All
were captured and inspected. `scripts/snapshot.sh --update-long-notes` scrolls
to the final example and asserts the scroll offset is nonzero, verifying that
long content can move while all three action buttons stay visible.
`--update-no-notes` exercises older-release compatibility. The native text view
keeps standard keyboard selection and scrolling; alert actions retain their
existing key equivalents. macOS 14/27 runtime behavior and publication by the
GitHub workflow remain unverified locally. See [Updates](../../README.md#updates)
for user-facing behavior.
