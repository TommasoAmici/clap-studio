---
name: bump-version-and-push
description: Bumps the Clap Studio version in scripts/bundle.sh as its own chore(release) commit and pushes main to publish the increased version. Use when the user asks to bump the version, cut or ship a release, or push the work to main.
disable-model-invocation: true
---

# Bump version and push

A push to `main` runs `.github/workflows/release.yml`, which publishes only when the app version exceeds the latest published version. This skill is the only place a push happens. Naming it is the user's go-ahead to push; do not push any other way.

## Steps

1. **Check the tree.** On `main`, with no uncommitted changes to tracked files (untracked `.cursor/` is fine, never commit it). If anything else is dirty, stop and tell the user what; do not commit it for them.
2. **Check the work.** Run `scripts/build.sh` (no new warnings) and the full `scripts/test.sh`. Stop on any failure.
3. **Regenerate the screenshots.** Run `scripts/media-kit.sh` and let it finish before the release commit; it rebuilds the debug app and a release seeder, then captures all eighteen 3200 × 2000 PNGs and two looping GIFs into `media/` from a scratch demo library. Stop on failure; the captures never touch the user's samples or library, and they only write under `media/`. It takes a few minutes, so run it once the build and tests passed and before anything is committed.
4. **Pick the version.** Read the current one from `CFBundleShortVersionString` in `scripts/bundle.sh`, and the commits since the last bump:
   `git log --oneline $(git log -1 --format=%H --grep='^chore(release)')..HEAD`
   - any `feat` (or `refactor`/`perf` that users will notice): minor, `0.19.0` becomes `0.20.0` (what past releases did)
   - only `fix`, `docs`, `test`, `chore`: patch, `0.19.0` becomes `0.19.1`
   - the user named a specific number: use it
   - nothing since the last bump: stop, there is nothing to release
   Run `python3 scripts/test-release-version.py` and check the chosen version with `python3 scripts/check-release-version.py --version X.Y.Z` using the existing GitHub credentials. The check must return `true`; stop on `false` or a failed lookup before committing release notes or the bump.
5. **Prepare the changelog.** Read `CHANGELOG.md` and the commits from step 4. Describe features, fixes, and other changes a musician will notice in plain English. Add any missing changes to `## Unreleased`, then move those entries into a new `## X.Y.Z` section below an empty `## Unreleased`; preserve earlier sections. Check the new version's notes with `python3 scripts/release-notes.py X.Y.Z` and `python3 scripts/test-release-notes.py`. Commit the changelog separately as `docs: release notes`.
6. **Bump.** Change only `CFBundleShortVersionString` in `scripts/bundle.sh`. Leave `CFBundleVersion` alone.
7. **Commit** on its own, nothing else in it: `chore(release): bump to X.Y.Z` (the fixed subject from `AGENTS.md`, longer than 25 characters on purpose; no body needed). Screenshots that step 3 refreshed and that changed files under `media/` go into this commit, since they are the release's own; when the run changed none, the commit holds only the version bump.
8. **Push** with `git push origin main`. Never force-push, never skip hooks. If the push is rejected, stop and report; do not rebase or merge on your own.
9. **Report** the new version, the commits it releases (one line each), and that the release workflow has started: `gh run list --workflow release.yml --limit 1`.

## Notes

- The workflow uses `CHANGELOG.md` notes for the app's version. Its extractor also includes pending entries from the publishing commit, so release preparation moves them into the version section first.
- The website and social images live in `media/` and deploy with the next push to `main`; step 3 keeps them fresh before the release commit.
- Files under `ROADMAP/` are not touched here: items are ticked off with the feature that ships them.
