# Misc improvements

## Work

Built in dependency order, smallest first.

- [x] Squid bank badge readable in dark mode.
- [x] Joined samples naming: a Name field, files `<name> 01`, `<name> 02`.
- [ ] Squid sending: pick the channel of each sample, or the same channel in following banks.
- [ ] Squid sending joined: join the selection before sending, one joined file per bank.
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
