---
name: work
description: Works through ROADMAP/TODO with parallel agents, one worktree per feature, TDD and atomic commits, moving finished features to ROADMAP/DONE.
disable-model-invocation: true
---

# Work

Work on all planned features in `ROADMAP/TODO` using parallel agents. You are the
coordinator: give each feature its own branch, worktree and worker, then integrate
verified results one at a time. Workers practice TDD and create atomic commits.

## Prepare and dispatch

A **feature** is one file in `ROADMAP/TODO/`; its `- [ ]` items are slices built
sequentially by that feature's worker. Parallelism is between files.

1. Record the original checkout, branch, `HEAD` and working-tree status. Read
   `AGENTS.md` and list all TODO files oldest first (`YYYY-MM-DD-topic.md`). If
   there are none, stop and report. Preserve existing local changes; worktrees
   start from committed history, so flag any feature that needs uncommitted work.
2. Read the features and identify dependencies. Queue independent features oldest
   first; start a dependent feature after its prerequisites have been integrated.
   Allocate a unique run directory outside the original checkout, within a
   writable location, and unique branch names such as `work/<run>/<topic>`.
3. Create an integration worktree and branch from the recorded `HEAD`. Create one
   worktree and branch per TODO file from the same base:
   `git worktree add -b <branch> <absolute-path> <base-sha>`. Record the mapping
   from roadmap file to branch, worktree and worker. Reuse existing work only
   after inspecting its status and ownership.
4. Spawn one worker per ready feature using the available agent tools. Run as
   many independent workers concurrently as capacity allows, reserving the
   coordinator's slot; queue the rest and dispatch when slots become available.
   Before dispatching a queued feature, advance its untouched branch to the
   current integration head so it includes completed prerequisites. If agent
   tools are unavailable, report the limitation and keep the same worktree
   isolation while processing features sequentially.
5. Give each worker its absolute worktree path, assigned roadmap file, base SHA,
   dependency context, and the worker loop and feature context guidance below.
   Workers read their assigned roadmap file, their worktree's `AGENTS.md` and
   relevant `README.md` section. Explicitly direct every command,
   edit, build and commit to that worktree: agents may share a default working
   directory. Each worker owns only its assigned feature and branch; the
   coordinator alone edits the integration worktree.

Keep dispatching ready features while other workers run or results are integrated.
Each worktree keeps its own build outputs and scratch `CLAP_DATA_DIR`. Coordinate
snapshot runs one at a time if they share the macOS app session.

## Worker loop

1. **Clarify** before writing code. Read the feature's `README.md` section and the
   code it touches. Send ambiguities about visible behaviour (wording, where a
   control lives, what happens to user files) to the coordinator, who batches
   them into a question using the available user-input tool. Continue independent
   work while awaiting an answer; settle implementation details from `AGENTS.md`
   and existing patterns.
2. **Build each item as a slice**, respecting dependencies and taking the
   smallest ready item first, each ending in its own commit:
   1. **Red**: write a failing Swift Testing test in `Tests/ClapCoreTests` for the `ClapCore` behaviour. Run `scripts/test.sh --filter SuiteName` and confirm it fails for the expected reason.
   2. **Green**: write the least code in `ClapCore` that passes it, then wire the UI in `ClapStudio` (`AppModel+Feature.swift`, views).
   3. **Refactor** with the tests green.
   4. **Verify**: `scripts/build.sh` with no new warnings, then the full `scripts/test.sh`. For UI changes, render with `scripts/snapshot.sh` (scratch `CLAP_DATA_DIR` if it edits the library) and read the PNG. When a slice touches bird features, also build with `NON_COMMERCIAL=0`.
   5. **Document** useful findings and decisions in the assigned roadmap file
      using Feature context below, while the reasoning is still fresh.
   6. **Commit** the slice: code, tests, the `README.md` update if behaviour changed,
      and the roadmap file with its context updated and the item ticked `- [x]`.
3. **Close** the feature once every item is ticked: `git mv ROADMAP/TODO/<file>
   ROADMAP/DONE/<file>` (create `ROADMAP/DONE/` if missing) and commit the move
   with a subject that follows `AGENTS.md`, such as `docs(roadmap): done`.
4. **Hand off** the branch and commit SHAs, checks run and their results, snapshot
   paths, decisions and blockers, and the roadmap file containing durable context.
   Leave the worktree clean and stop editing it.
   Do not merge, push, remove worktrees or pick another feature yourself.

UI-only items with no `ClapCore` logic to test still go through Verify, with the snapshot as the check.

## Feature context

Each worker maintains a `## Implementation context` section in its assigned
feature's roadmap Markdown file, alongside the original brief and checklist.
Read existing notes before choosing an approach, and update them with each slice
and before a blocked handoff. This context travels with the file into
`ROADMAP/DONE/`, so a future maintainer can understand and revisit the work.

Record information that would otherwise require rediscovering the reasoning.
Use short paragraphs or bullets, with subheadings only when they help:

- Decisions and their reasons: constraints, tradeoffs, user clarifications, and
  alternatives actually considered or tried, including why they were set aside.
- Implementation landmarks: repository-relative paths and key symbols, how the
  relevant pieces interact, and invariants a refactor must preserve.
- Surprising findings: platform or API limitations, failed approaches, and
  workarounds, with the evidence or conditions that explain them.
- Validation that matters later: relevant test suites, reproduction commands,
  measurements, and gaps such as checks that require unavailable hardware.
- Remaining limitations, deferred work, and open questions, including what would
  justify revisiting a decision or unblock the next slice.

Keep notes specific to the feature and proportional to what was learned; include
only applicable points. Distinguish verified findings from assumptions and
unresolved questions. Update superseded notes to reflect the current approach,
retaining earlier decisions when their rationale still explains the design.
Use repository-relative links that remain valid after the move to DONE. Keep
user-facing behaviour in `README.md`; link to it instead of duplicating it.
Capture durable knowledge rather than a transcript of commands or progress.

## Integrate

1. Review each handoff against its roadmap checklist and inspect the diff for
   unrelated changes. Integrate ready branches sequentially in the integration
   worktree with `git merge --no-ff --no-commit <feature-branch>`.
2. Resolve conflicts with the feature worker's input. Check README and roadmap
   changes and shared code even when Git reports no conflict. Ensure feature
   context matches the combined implementation, and record any integration
   decisions in the affected feature's roadmap file. For concurrent
   schema changes, preserve migrations from the integration branch and renumber
   incoming migrations with the corresponding `currentVersion` update.
3. Before committing the merge, run `scripts/build.sh` with no new warnings and
   the full `scripts/test.sh` on the combined result. Repeat the relevant UI
   snapshot and commercial build checks from Verify. Fix integration failures
   and rerun affected checks until the combined feature passes, then commit the
   merge following `AGENTS.md`. If it remains blocked, abort that pending merge,
   retain the feature branch and worktree, and continue independent features.
4. After all available features are integrated, fast-forward the original branch
   to the integration branch only if the original checkout is clean and its
   branch and `HEAD` still match the recorded state. Otherwise leave the tested
   result on the integration branch and report how to bring it in after local
   work is settled.
5. Remove only clean worker worktrees whose commits are reachable from the
   integration branch. Retain branches and any blocked or unintegrated
   worktrees, and report their locations. Keep the integration worktree when
   its result has not been brought into the original branch.

## Commits

Follow the format in `AGENTS.md`: `type(scope): subject` of at most 25 characters, and a 72-column body saying what changed and why for `feat`, `fix` and `refactor`. Every commit builds and passes the full test suite. Leave pushing to the user: a push to `main` runs the release workflow, which publishes only an increased app version.

## When blocked

If a slice can't go green (missing hardware such as a Squid USB stick, an API that
macOS 14 lacks, a conflict with an invariant in `AGENTS.md`), the worker stops on
that feature and reports to the coordinator. Leave it in `ROADMAP/TODO/` with
finished items ticked and preserve its branch and worktree. Record the blocker,
evidence, attempted approaches, and what is needed to resume in the feature
context before handing it off. The coordinator
explains the blocker and asks how to continue while other independent workers
carry on. Integrate verified partial slices only when their dependencies and the
combined checks pass; the feature stays in TODO until all its items are done.

## Report

Report each integrated feature moved to `ROADMAP/DONE/` with its commits and
checks, anything left in `ROADMAP/TODO/` and why, and decisions the user may want
to revisit. Distinguish integrated work from completed branches awaiting
integration. Include the integration branch, whether the original branch was
advanced, and retained branches and worktree paths so the run can be resumed.
