# Send to Squid Salmple

## Work

- [x] Overwrite when sending
- [x] Long list of warnings UI
- [ ] ALM Salmple preset for joined samples
- [ ] Collapsible left sidebar sections

## Overwrite when sending

When I send to Squid and I select `Same channel in following banks`, I should be able to
overwrite existing banks if the banks I'm starting from already contain samples.

It currently shows a warning `Bank N was skipped: its channel M already holds a sample.`,
I would do it the other way around and warn the user that the channel will be overwritten.

## Long list of warnings UI

When the list of warnings is too long, the UI breaks: let's make this area scrollable instead.
I think a nice approach would be to have a scrollable area with a title that includes a badge
with the count of warnings so users know at a glance how many warnings there are
without scrolling the entire list.

![screenshot](image.png)

## ALM Salmple preset for joined samples

The default silence between joined samples is 0.25s, let's lower it to 0.1s

## Collapsible left sidebar sections

I'd like to make the left sidebar sections (e.g. Filters, Collections, Categories, Moods, etc.)
collapsible and sortable.

The app should remember across restarts whether a section was collapsed or not.

Add a settings page to control the order of the sections in the sidebar. Similar to Finder.app.

I also want the user to be able to hide a section from this menu or right clicking the
section's title.

## Implementation context

### Overwrite when sending

- `SquidChannelPlan` no longer skips banks. In the `sameChannel` rule (also used by *Join samples before
  sending*) a sample always keeps its bank; when that channel already holds a sample the plan adds the
  non-blocking `SquidPlanIssue.overwritesChannel(bank:channel:)`, shown as *Bank 3: channel 1 already holds a
  sample and will be overwritten.* (orange, one line per bank). `skippedBank` was removed. The channel number
  of an affected row also turns orange. No toggle and no confirmation, as decided.
- `SquidExporter.place` got `overwrite: Bool = false`. Off, a taken channel still throws as before, so
  collection sends (always into a new set) and any other caller keep the safe behaviour. The sheet passes
  `overwrite: sameChannel`; `SquidJoinedSender` passes `true`.
- Overwrites go through the new `SquidOverwrite` (ClapCore): write a clone of each new sample into a hidden
  `.clap-new-<token>-<channel>` folder next to the old channel folder, compare it byte for byte with the
  staged file, and only after every clone is verified swap by renaming (old channel folder, and any loose
  `Chan-00N.wav` of older firmware, into a hidden `.clap-old-<token>` folder in the bank; clone into place).
  Every rename is journalled; a failure undoes them in reverse and removes new banks and clones, so a bank is
  never half written. On success the hidden folders (with the replaced samples) are deleted.
- Decision: replaced samples are deleted, not moved to the Trash. Overwriting is what the musician asked for
  and a Trash trip per channel would clutter a USB stick (`.Trashes` on FAT32). *Replace it* for a whole
  bank still goes to the Trash as before.
- Decision: the blocking `channelTaken` error (*Channel X of bank Y already holds a sample. Pick another
  channel; nothing is overwritten.*) stays, but only for the one-bank rule (adding to an existing bank and
  choosing a taken channel by hand). That message is still true there, the sheet offers *Replace it* for
  that bank, and the request only covered following banks. Hand-picking a taken channel while in
  *Same channel in following banks* mode is an overwrite like the others (same warning).
- Landmarks: `Sources/ClapCore/Squid/SquidChannelPlan.swift`, `SquidOverwrite.swift`,
  `SquidExporter+Place.swift`, `SquidExportItems.swift`, `AppModel+SquidExport.swift` (`SquidPlan.banks`
  gained `overwrite`). Tests: `SquidChannelPlanTests`, `SquidOverwriteTests`, `SquidJoinedSendTests`.
- Surprise: the bank-level `export` and `add` paths are untouched; only `place` can overwrite.
- Limitation: if the app is killed between the swap steps, hidden `.clap-new-*`/`.clap-old-*` folders can
  stay in a bank. They start with a dot, so the module and the app ignore them.

### Long list of warnings UI

- New `SquidPlanIssuesView` (ClapStudio) replaces the loose lines under the sample list: a `Warnings` title
  with a capsule count badge, and the messages in a `ScrollView` limited to 96 pt (about six lines). The
  height is measured with a preference key so one or two warnings take only the space they need, which a
  plain `ScrollView` with `maxHeight` would not do inside the sheet's `fixedSize`. Badge and text use system
  colours (red when anything blocks the send, orange otherwise), so light and dark both work; the title
  row reads as "Warnings, N" to VoiceOver. The list uses `.scrollBounceBehavior(.basedOnSize)` (macOS 13.3+).
- Decision: blocking issues are listed first (`SquidChannelPlan.orderedIssues`, tested), so a red message is
  never hidden below the fold of a long orange list.
- Verification: `scripts/snapshot.sh --media --usb Studio --send-bank 12 --send-same 1 --send-crowded`
  (new `--send-crowded` option; it pretends banks 2 to 40 of the set are full, in memory only). Checked in
  light and dark with 11 and 29 warnings: the sheet keeps its size and the list scrolls.
  PNGs: `/tmp/clap-work-HiAGrm/snapshots/squid-warnings-{light,dark}.png`.
- Landmarks: `Sources/ClapStudio/Views/SquidPlanIssuesView.swift`, `SquidExportItems.swift`,
  `DebugSnapshotSquid.swift`; `SquidSet` gained a public `init(name:banks:)` for the snapshot helper.
