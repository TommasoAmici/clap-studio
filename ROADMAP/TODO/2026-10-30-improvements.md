# Misc improvements

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
