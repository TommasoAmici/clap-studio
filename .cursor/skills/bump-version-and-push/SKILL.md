---
name: bump-version-and-push
description: Bumps the Clap Studio version in scripts/bundle.sh as its own chore(release) commit and pushes main, which publishes a GitHub release. Use when the user asks to bump the version, cut or ship a release, or push the work to main.
disable-model-invocation: true
---

# Bump version and push

A push to `main` runs `.github/workflows/release.yml` and publishes a release, so this skill is the only place a push happens. Naming it is the user's go-ahead to push; do not push any other way.

## Steps

1. **Check the tree.** On `main`, with no uncommitted changes to tracked files (untracked `.cursor/` is fine, never commit it). If anything else is dirty, stop and tell the user what; do not commit it for them.
2. **Check the work.** Run `scripts/build.sh` (no new warnings) and the full `scripts/test.sh`. Stop on any failure.
3. **Pick the version.** Read the current one from `CFBundleShortVersionString` in `scripts/bundle.sh`, and the commits since the last bump:
   `git log --oneline $(git log -1 --format=%H --grep='^chore(release)')..HEAD`
   - any `feat` (or `refactor`/`perf` that users will notice): minor, `0.19.0` becomes `0.20.0` (what past releases did)
   - only `fix`, `docs`, `test`, `chore`: patch, `0.19.0` becomes `0.19.1`
   - the user named a specific number: use it
   - nothing since the last bump: stop, there is nothing to release
4. **Bump.** Change only `CFBundleShortVersionString` in `scripts/bundle.sh`. Leave `CFBundleVersion` alone.
5. **Commit** on its own, nothing else in it: `chore(release): bump to X.Y.Z` (the fixed subject from `AGENTS.md`, longer than 25 characters on purpose; no body needed).
6. **Push** with `git push origin main`. Never force-push, never skip hooks. If the push is rejected, stop and report; do not rebase or merge on your own.
7. **Report** the new version, the commits it releases (one line each), and that the release workflow has started: `gh run list --workflow release.yml --limit 1`.

## Notes

- Release notes come from the workflow, not from this skill.
- Files under `ROADMAP/` are not touched here: items are ticked off with the feature that ships them.
