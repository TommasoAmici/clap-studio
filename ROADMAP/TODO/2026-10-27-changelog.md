# Changelog

Please keep a user readable changelog that lists all added features, bug fixes and other things
that might interest users.

When preparing a release, update the changelog (update the bump-version-and-push skill with these
instructions).

When creating a GitHub release, add the release notes for the current version in GitHub.

When showing the update dialog, include the release notes.

- [x] Keep a musician-readable changelog and include it when preparing and publishing releases.
- [ ] Show each release’s notes in the update dialog.

## Implementation context

GitHub publishes a build for every push to main, including pushes without a
marketing-version bump. The release workflow will include pending changes plus
the current version’s notes. Release preparation moves pending entries into the
new version section, while preserving earlier history.

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
