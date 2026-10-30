# Misc improvements

## Work

Built in dependency order, smallest first.

- [x] Squid bank badge readable in dark mode.
- [x] Joined samples naming: a Name field, files `<name> 01`, `<name> 02`.
- [x] Squid sending: pick the channel of each sample, or the same channel in following banks.
- [x] Squid sending joined: join the selection before sending, one joined file per bank.
- [ ] Nested collections: one level of sub-collections.
- [ ] Send a collection to Squid: banks of a new set, or Pool folders.

## Squid sending

When sending samples to Squid I'd like to be able to select which channel they go to,
currently it's not possible to override this.

## Squid sending joined

It'd be great if I could select multiple samples, select Send to Squid and then have
the samples joined before being loaded in banks.

For example, if I select 20 kicks samples, I'd like to send them to channel 1 of the
Squid banks as a joined audio sample. If the joined audio needs to be split in multiple
separate files, they should go to the next bank.

For example, of the 20 kicks, maybe 11 go joined to channel 1 of the first bank and the
next 9 go joined to channel 1 of the second bank.

## Squid sending multiple files

It's currently possible to send files to squid to fill up a bank from channel 1 through 8.
I want to also have the option of sending each file to the same channel in subsequent banks.
For example, if I select 4 snare sounds and I want to send them to channel 2 of banks 1, 2, 3, and 4.

## Joined samples naming

When joining samples, I'd like to be able to set a name for the generated files.
For example `kicks` and the files generated would be `kicks 1` and `kicks 2`.

I'd also like to change the numbering to have one leading zero so `01` instead of `1`.

## Squid bank badge background color

In dark mode, the badge's background color with white text is not very readable, plase improve that
![bg color](image.png)

## Nested collections

I'd like to be able to add sub-collections to a collection. For example, I want to create
the collection "Party #23" and nested inside "Opening". There should only be one level of
nesting.

## Send collection to Squid

I want to be able to send a collection to Squid. This context menu option should only
be visible if a Squid drive is connected.

If a collection has nested collections, each nested collection should become a bank in a set.
If a nested collection has too many samples for a bank (i.e. more than 8). Show the user a
warning and stop.

If a collection doesn't have nesting, then it should go to the pool under as a new folder.
If a collection has too many samples, they should be broken up in nested folders according
to the Salmple manual so that they work ok in the pool.

## Implementation context

**Bank badge.** The free-channel count was white on `Color.orange` in two places (sidebar bank row,
bank card). In dark mode the system orange is light, so white on it was hard to read; in light mode it is a
deep orange and white is fine. Both now use `FreeSlotsBadge` (`Views/SquidNameViews.swift`): near-black number in
dark mode, white in light mode, same orange fill. Checked with `scripts/snapshot.sh --media --usb Studio
--appearance dark|light` on a library seeded by `ClapMediaSeed` (the Squid demo stick only exists in a seeded
media library; copy it first because a snapshot indexes the stick into the library).

**Joined samples naming.** `JoinNaming` (`Sources/ClapCore/Join/JoinNaming.swift`) builds `<name> NN.wav`
(`%02d`, so 100 stays `100`) and cleans the typed name with `ExportNaming.sanitize`, trims it, caps it at 100
characters and falls back to "Joined" when nothing usable is left. `JoinExporter.export` /
`exportWithRegions` take a `name:` (default "Joined"), and the existing `SampleExporter.uniqueURL` still adds
" 2" on a clash (`kicks 01 2.wav`). The name is not part of `JoinSettings`: those are the limits saved in
presets, and a preset that also fixed a name would make two presets that differ only by name. It lives in
`JoinState.name`, reset to "Joined" in `openJoin` and kept when the folder chooser is cancelled and the sheet
comes back. The sheet shows the first two resulting file names as a hint. Existing tests that used a source
called `Joined 1.wav` to check a clash now use `Joined 01.wav`. Validated with `scripts/snapshot.sh --join`.
Joined files made when sending to Squid will use the same names if the sheet shows them (see that item).

**Squid channel selection and same channel in following banks.** Both items are one design. The pure planning is
`SquidChannelPlan.make` (`Sources/ClapCore/Squid/SquidChannelPlan.swift`): per sample an optional chosen
channel plus a rule, `.fillBank` (channels 1, 2, 3… of one bank, or the free ones of an existing bank) or
`.sameChannel(n)` (channel n of the start bank, then the next bank, and so on). It returns a bank and channel per
sample and issues. Blocking issues: two samples on one channel, a chosen channel that already holds a sample,
or running past bank 99. Notes that do not block: more samples than free channels (as before, the first ones
are sent and the rest say "not sent") and banks skipped in same-channel mode because their channel is taken.
Decisions: samples without a pick take the lowest channels nobody asked for; in same-channel mode a bank whose
channel is taken is skipped, not overwritten, and the sheet says which. "Replace it" is only offered in
the single-bank mode, because replacing several banks would trash more than the musician asked for. New banks
all take the one name typed in the sheet; an existing bank keeps its own name and samples.
Writing goes through `SquidExporter.place` (`SquidExporter+Place.swift`): it checks every slot first,
converts everything in a temporary folder, and only then writes; if writing fails part way it removes what
the call made. `SquidExporter.add` stays for the existing tests and callers but the sheet no longer uses it.
The sheet is split: `SquidExportItems.swift` holds the list with the channel menus. `SquidPlan` is now
`.banks(set:firstBank:bankName:slots:replace:)` or `.pool`; `sendToSquid` pairs each sheet row with its slot,
so a sample that left the library still holds its channel. Chosen channels live in `AppModel.squidChannels`
(by sample, cleared when the sheet opens). Snapshots: `scripts/snapshot.sh --usb Studio --send-bank [pick]
[--send-same N]` on a seeded media library (see the badge note).

**Squid sending joined.** `SquidJoinedSender.send` (`Sources/ClapCore/Squid/SquidJoinedSender.swift`) joins with
`JoinExporter.exportWithRegions(settings: .almSalmple, name:)` into a temporary folder, plans the banks with
`SquidChannelPlan` (`.sameChannel`, so a bank whose channel is taken is skipped), and writes with
`SquidExporter.place`; the temporary folder is removed on every path and nothing is written unless every
joined file has a bank. A joined file must reach the stick unchanged, because re-rendering it through
`TrimExporter` would drop the cue markers that are the point of joining, so `SquidSource.keepAudio` makes `place`
copy it (the category tag is still appended: it is a trailing `LIST` chunk, which leaves the cues alone). The
tag is set only when every selected sample has the same category. Decision: level matching is not applied to
joined files (the switch is greyed out and the sheet says so) because matching would have to be done per
sound before joining and `JoinSourceRenderer` has no such step. The ALM preset limits are `JoinSettings.almSalmple`
and are fixed in this sheet; the Join sheet's own presets are not offered here. The sheet cannot know the file
count before rendering, so it shows an estimate from lengths (`JoinPlanner.estimatedFileCount`,
`JoinSource.estimatedSeconds`); the authoritative check runs in the sender, which stops with a message and
writes nothing when the banks run out. Joined mode is for banks only (not the Pool) and does not offer
"Replace it". File names use `JoinNaming` with the sheet's own File name box (default "Joined"). Snapshot:
`scripts/snapshot.sh --usb Studio --send-bank 20 --send-join` on a seeded media library.
