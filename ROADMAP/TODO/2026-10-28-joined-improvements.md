# Joined samples improvements

I'd like the joined samples to be shown in a better way in the app.
A joined sample should hold links to the samples it contains.
They should be shown separately from normal samples, loops, and field recordings.
I'd like to be able to expand a joined sample row and see all the sub samples it contains.

## Work

- [x] Track the source and bounds of every piece in each joined file.
- [x] Keep source links for joined files, including files outside indexed folders.
- [x] Show joined samples separately from other sample types.
- [x] Expand a joined sample row to show its source samples.

## Implementation context

Joined WAVs are exported independently of the library; their existing cue labels do
not reliably identify source files. New exports need durable library links, and
existing exports cannot be linked from names alone. File plans must retain each
piece's source index and rendered-frame offsets, including continuations and
repeated source selections.

`JoinExporter.exportWithRegions` returns each published URL with the exact
`JoinPlanner` regions; the existing URL-only export API remains available.

`LibraryStore+Joined.swift` stores published paths and ordered pieces in schema
version 15. Source IDs use `ON DELETE SET NULL`; when an export finishes, its source path is
checked as well because a removed sample ID can be reused. Names and paths survive
removing a source folder. Export reports a separate error if persistence fails.

The Joined type filter matches indexed records against normalized root and
relative paths. When a rescan recognises a rename by fingerprint,
`LibraryStore.sync` moves the stored links with the sample. After exporting,
only the joined flag is updated on current records, preserving edits made while
the export ran. All includes joined files; other type filters exclude them.

Schema version 16 stores a streaming SHA-256 of each published joined file.
Scans forget links on a full-content mismatch, including before the output is
first indexed. Ordinary sample move detection keeps its cheaper fingerprint.
An unreadable file keeps its links as unverified and is shown as joined only
after a successful rescan. Version 15 links without an
old fingerprint use the indexed fingerprint when available; otherwise the first
readable scan is the baseline. Export, first indexing, changed-file verification,
and app-authored WAV cue or metadata writes read each affected joined output in
full before taking the database lock; unchanged verified outputs are not reread.
Device, inode, size and modification time are checked around hashing and against
the scan. A same-size, same-time replacement between enumeration and hashing
cannot be identified as a race because the scan does not record file identity.
If an app-authored rewrite cannot be fingerprinted, links remain unverified;
a later mismatch removes them instead of accepting unknown bytes. A move can
only carry links when the library recognizes it within an indexed root;
moving an unindexed output or moving between roots is not tracked.

At 100,000 synthetic rows and 32 embedding dimensions, `scripts/bench.sh`
reopened the library in 0.160 s with either no joined paths or 1,000 joined
paths. Unchanged rescans took 0.086 s and 0.165 s respectively. A warm 50 MiB
joined-file digest took 0.029 s on this Mac (temporary instrumentation).

The library table uses native disclosure controls and retains the order and
duplicates of source pieces. Sources can be selected or auditioned when present;
removed sources retain their name. Link fetching is cached, cancellable, and
refreshed on library changes. Collapsing a selected child keeps selection on the
remaining rows or the parent. Inspected snapshots include expanded and missing
sources; native accessibility automation successfully opened a disclosure and
exposed both source rows, but did not expose selected-row state for arrow-key
verification. Tested on macOS 26.7.2; macOS 14 runtime was not available.
Live Apple guidance could not be fetched because DNS was unavailable.
