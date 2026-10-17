---
name: work
description: Works through the planned features in ROADMAP/TODO one by one with TDD and atomic commits, moving each finished feature to ROADMAP/DONE. Use when the user runs /work or asks to work on the roadmap.
disable-model-invocation: true
---

# Work

Please take a look at `ROADMAP/TODO` and work on all planned features. When a feature is done, move it to `ROADMAP/DONE` and pick up the next if available. As you work, create atomic commits with buildable and tested changes. Practice TDD. Ask for clarifications if needed.

## Loop

A **feature** is one file in `ROADMAP/TODO/`; its `- [ ]` items are the slices to build. Take files oldest first (they are named `YYYY-MM-DD-topic.md`).

1. **Pick** the oldest file in `ROADMAP/TODO/`. If there is none, stop and report what shipped.
2. **Clarify** before writing code. Read the feature's `README.md` section and the code it touches. When an item is ambiguous about behaviour the user would see (wording, where a control lives, what happens to user files), ask with the AskQuestion tool, batching all open questions for the feature in one ask. Settle implementation details yourself from `AGENTS.md` and existing patterns.
3. **Build each item as a slice**, smallest first, each ending in its own commit:
   1. **Red**: write a failing Swift Testing test in `Tests/ClapCoreTests` for the `ClapCore` behaviour. Run `scripts/test.sh --filter SuiteName` and confirm it fails for the expected reason.
   2. **Green**: write the least code in `ClapCore` that passes it, then wire the UI in `ClapStudio` (`AppModel+Feature.swift`, views).
   3. **Refactor** with the tests green.
   4. **Verify**: `scripts/build.sh` with no new warnings, then the full `scripts/test.sh`. For UI changes, render with `scripts/snapshot.sh` (scratch `CLAP_DATA_DIR` if it edits the library) and read the PNG. When a slice touches bird features, also build with `NON_COMMERCIAL=0`.
   5. **Commit** the slice: code, tests, the `README.md` update if behaviour changed, and the item ticked `- [x]` in its roadmap file.
4. **Close** the feature once every item is ticked: `git mv ROADMAP/TODO/<file> ROADMAP/DONE/<file>` (create `ROADMAP/DONE/` if missing) and commit it as `docs(roadmap): <topic> done`.
5. Go back to step 1.

UI-only items with no `ClapCore` logic to test still go through Verify, with the snapshot as the check.

## Commits

Follow the format in `AGENTS.md`: `type(scope): subject` of at most 25 characters, and a 72-column body saying what changed and why for `feat`, `fix` and `refactor`. Every commit builds and passes the full test suite. Leave pushing to the user: a push to `main` publishes a release.

## When blocked

If a slice can't go green (missing hardware such as a Squid USB stick, an API that macOS 14 lacks, a conflict with an invariant in `AGENTS.md`), stop on that feature, leave it in `ROADMAP/TODO/` with the finished items ticked, explain the blocker to the user and ask how to continue.

## Report

When the loop ends, list each feature moved to `ROADMAP/DONE/` with its commits, anything left in `ROADMAP/TODO/` and why, and any decisions taken without asking that the user may want to revisit.
