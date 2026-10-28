# Joined samples improvements

I'd like the joined samples to be shown in a better way in the app.
A joined sample should hold links to the samples it contains.
They should be shown separately from normal samples, loops, and field recordings.
I'd like to be able to expand a joined sample row and see all the sub samples it contains.

## Work

- [x] Track the source and bounds of every piece in each joined file.
- [x] Keep source links for joined files, including files outside indexed folders.
- [x] Show joined samples separately from other sample types.
- [ ] Expand a joined sample row to show its source samples.

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
