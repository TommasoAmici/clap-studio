# Send to Squid Salmple

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
