# Send to Squid Salmple

## Work

- [x] Overwrite when sending
- [x] Long list of warnings UI
- [x] ALM Salmple preset for joined samples
- [x] Collapsible left sidebar sections

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

### ALM Salmple preset for joined samples

- The one default lives in `JoinSettings.init` (`silenceSeconds: 0.1`); `JoinSettings.almSalmple` is
  `JoinSettings()`, so the built-in *ALM Squid Salmple* preset, the Join sheet's starting values, the Squid
  joined sender and the sheet's file-count estimate all follow it. The `.help` text in `SquidExportSheet`
  and the README (Join samples and Squid Salmple paragraphs) say 0.1 seconds now.
- Saved presets (`join.presets` in UserDefaults) store the whole `JoinSettings` as JSON, so presets saved
  earlier keep their 0.25 s; `settingsSavedBeforeKeepTheirOwnSilence` decodes such a preset to prove it. A
  preset saved at 0.25 s now shows by its own name in the Join sheet, not as the built-in one, because the
  sheet matches the built-in preset by equality.
- Tests that used the default: `joinsAudioWithSilentGapsAndNewNamedRegions` (13,230 frames, second cue at
  8,820), the 20 kicks Squid test (now 10 + 10 on banks 1 and 2), the file-count estimate (2), and
  `notEnoughBanksStopsBeforeAnythingIsWritten` (30 kicks so three files still overrun banks 98 and 99).
  Tests with an explicit silence are untouched.
- Verification: `scripts/snapshot.sh --media --join` shows *Silence between sounds* as 0,1 (locale comma).
  PNG: `/tmp/clap-work-HiAGrm/snapshots/join-default-silence.png`.

### Collapsible left sidebar sections

- Pure logic is `SidebarLayout` and `SidebarSection` in `Sources/ClapCore/Library/SidebarLayout.swift`
  (13 tests in `SidebarLayoutTests`): the known sections in default order, the stored order merged with
  them (unknown and repeated ids dropped; a section missing from the stored order is inserted after the
  section that precedes it by default, so one added by a later version lands where it belongs), the hidden
  and collapsed sets, drag moves (`move(fromOffsets:toOffset:)`, same semantics as SwiftUI's), one-step moves
  among the listed sections that jump over hidden ones, `reset()`, and load/save with `UserDefaults`.
  A value of the wrong kind in a key is ignored. Keys: `sidebar.order`, `sidebar.hidden`,
  `sidebar.collapsed` (arrays of section ids).
- `AppModel.sidebarLayout` holds it (saved in `didSet`); `AppModel+Sidebar.swift` decides which sections have
  something to show now (`availableSidebarSections`: categories, moods and tags only when non-empty, USB
  Drives only while a drive is connected) and hides sections.
- `SidebarSectionBox` wraps each section in a native `Section(isExpanded:)` (macOS 14), with the title's
  context menu (`SidebarSectionMenu`): Collapse/Expand, Move Up, Move Down, Hide <Section>, Show Hidden
  Section submenu, Sidebar Settings… `SidebarView` now loops over `listedSidebarSections`;
  `CollectionsSidebarSection` and `SquidSidebarSection` use the box instead of a bare `Section`. The USB
  section keeps its existing title, "USB Drives" (the request said "Squid drives").
- Settings: new first tab *Sidebar* (`SidebarSettingsView`), a `List` with `.onMove` (drag to reorder), a
  checkbox per section, up/down arrow buttons (keyboard and VoiceOver; also "Move Up"/"Move Down" custom
  accessibility actions and a context menu) and a Reset button. `SettingsTab` remembers the last tab
  (`settings.tab`); a tab missing from the build (Birds with `NON_COMMERCIAL=0`) falls back to Sidebar.
  The context menu's *Sidebar Settings…* opens Settings with `showSettingsWindow:` on that tab.
- Decisions (ambiguous, most conventional macOS behaviour):
  - Hiding the section that holds the current selection goes back to All Samples (Filters hidden with All
    Samples selected is left alone), so no filter is active without a sidebar row for it. Folding a section
    keeps the selection (as Finder and Mail do); filters set from the filter bar are unaffected.
  - Everything is hideable, Filters included. Hidden sections come back from Settings or from the *Show
    Hidden Section* submenu of any title's menu; no View menu entry was added, as asked.
  - A section with no content (no moods yet, no drive) is not listed whatever its setting; the Settings
    row says so. Hidden stays hidden while it has no content.
  - *Reset* restores order and hidden sections but leaves the folded state alone.
- Keyboard: the sidebar's own titles are not keyboard focusable in SwiftUI, so the keyboard route is
  Settings > Sidebar (Tab to the checkboxes and arrows). Full keyboard fold of a title is a limitation.
- Verification (`scripts/snapshot.sh`, scratch library from `ClapMediaSeed`): new options `--sidebar-order`,
  `--sidebar-hidden`, `--sidebar-collapsed` (passed as launch arguments, so preferences are not changed)
  and `--settings` (the Settings view in a plain window; the real Settings window cannot be opened from
  the snapshot hook). PNGs in `/tmp/clap-work-HiAGrm/snapshots/`: `sidebar-default.png`,
  `sidebar-custom.png` (Folders first, Collections and Categories folded, Moods hidden),
  `sidebar-settings.png`. Builds with and without `NON_COMMERCIAL` are clean.
- Not verified by hand: clicking a title's arrow and dragging rows in Settings (no GUI scripting
  available); both use stock SwiftUI (`Section(isExpanded:)`, `onMove`).
