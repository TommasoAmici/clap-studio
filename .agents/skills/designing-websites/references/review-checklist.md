# Review checklist

Use this when reviewing a page or a whole site. Work top to bottom; the earlier sections invalidate the later ones.

Mark each item **pass**, **fail**, or **n/a**. A fail needs a fix, not a note.

## A. Content and purpose

- [ ] Each page has one named reading task: read, scan, browse, compare, or decide.
- [ ] The primary content is visible without scrolling past decoration.
- [ ] The longest headline, longest word, longest URL, and longest number have been tested.
- [ ] Empty, loading, error, and no-results states exist and are designed.
- [ ] Content that runs out does not leave a broken layout (short cards, one-item grids).
- [ ] Translated text at +35% length does not break the layout.

## B. Type system

- [ ] One family, or a pair with a stated reason to be together.
- [ ] Five to seven sizes in use, from one scale; no orphan sizes invented per section.
- [ ] Body text is at least 16 px.
- [ ] Real italics, bolds, and small caps; nothing synthesised by the browser.
- [ ] Display face is not used for body copy; text face is not blown up to poster size without an optical cut.
- [ ] Language coverage matches the locales shipped (Vietnamese, Greek, Cyrillic, Arabic, CJK, Indic).
- [ ] Fallback stack is deliberate and metric-matched; the swap does not shift layout.
- [ ] Licences for every font are recorded and permit web use.

## C. Text setting

- [ ] Prose measure is 45–75 characters (about 60–70 `ch`).
- [ ] Body line height is 1.5–1.7; headings 1.0–1.25.
- [ ] Line heights land on a common rhythm; no accidental 27.6 px lines in a 24 px system.
- [ ] Paragraphs use a space **or** an indent, not both; no indent after a heading.
- [ ] Alignment is flush left for Latin prose (or justified with a long measure and hyphenation).
- [ ] Rag has no wedges, moons, stairsteps, or single-word last lines that editing could fix.
- [ ] Caps are letter-spaced slightly; lowercase is never letter-spaced.
- [ ] Numerals are tabular where they must align, proportional or oldstyle in prose.
- [ ] Real quotes, en dashes, em dashes, primes, and ellipses; no straight quotes or `--`.
- [ ] Non-breaking spaces in units, ranges, and initials where the language expects them.
- [ ] Links are distinguishable by more than colour.

## D. Layout and grid

- [ ] The page has a stated grid family: manuscript, column, modular, hierarchic, or compound.
- [ ] Column count follows the content, not a framework default.
- [ ] Gutters are consistent and are multiples of the body line height.
- [ ] Margins are about twice the gutter, or deliberately different for a reason.
- [ ] Every element aligns to a column edge, a row edge, or a baseline.
- [ ] Images align to column and row edges, or clearly and deliberately do not.
- [ ] No image edge falls ambiguously mid-column.
- [ ] The page is not centred by default; asymmetry or symmetry is a choice.
- [ ] White space is considered as shapes, not as leftover.
- [ ] Rows are not relied on where content reflows; top edges of grouped elements align.

## E. Hierarchy and grouping

- [ ] The first thing seen is the most important thing on the page.
- [ ] Grouping passes the squint test: groups are visible before elements.
- [ ] Space inside a group is smaller than space between groups.
- [ ] Headline sits closer to its text than to the previous section.
- [ ] One primary action per view; secondary actions are visibly secondary.
- [ ] Heading levels are semantic and sequential; one `<h1>` per page.
- [ ] Visual order and DOM order agree, or both remain coherent when they differ.
- [ ] The same level is styled the same way everywhere.
- [ ] There is a "crunchy bits" layer — labels, captions, metadata — not just headline and body.

## F. Deliberate disruption

- [ ] Every break from the grid has a nameable reason: meaning, emphasis, pacing, or narrative.
- [ ] There are no more than two or three broken rules, and they are written down.
- [ ] One strict alignment anchor survives beside every broken element.
- [ ] Only one axis is broken at a time.
- [ ] Removing the break would lose something; if not, it is decoration.
- [ ] The break survives reflow and does not create horizontal scroll.

## G. Responsive

- [ ] Tested at 320, 375, 768, 1024, 1440, and 2560 px.
- [ ] Tested at 200% browser zoom and with a large default font size.
- [ ] No horizontal scrolling for prose at any width.
- [ ] Measure stays within 45–75 characters on every breakpoint.
- [ ] Breakpoints fall where the content breaks, not at device names.
- [ ] Components use container queries where their slot varies.
- [ ] Images keep their aspect ratio; faces and data are not cropped.
- [ ] Nothing is hidden on mobile that matters on desktop.
- [ ] Tap targets are at least 24 px, ideally 44 px, with spacing between them.
- [ ] Sticky headers do not cover anchors, focus, or the top of the content.

## H. Accessibility

- [ ] Body contrast ≥ 4.5:1; large text and UI ≥ 3:1; checked in light and dark mode.
- [ ] Colour is never the only carrier of meaning (errors, status, links, charts).
- [ ] Every image has alt text, or `alt=""` if decorative.
- [ ] Form fields have persistent visible labels; placeholders are not labels.
- [ ] Errors are described in words at the field and say how to fix them.
- [ ] Buttons and links name their action; no "Click here" or "Read more" without context.
- [ ] `lang` is set on the document and on foreign-language passages.
- [ ] Landmarks and headings allow skipping to the main content.
- [ ] Full keyboard access, logical tab order, visible focus, no traps.
- [ ] `prefers-reduced-motion` is respected; autoplay can be paused.
- [ ] Works in forced-colours / high-contrast mode.
- [ ] Text over images has a contrast layer at every scroll position.

## I. Multiscript

- [ ] `dir="rtl"` and logical properties used where RTL is supported.
- [ ] Directional icons mirrored; objects and logos not mirrored.
- [ ] Arabic has a real font, more line height, and no faux italic.
- [ ] CJK has no letter-spacing, adequate line height, and correct alignment by character centre.
- [ ] Korean is set slightly smaller with more leading than Latin.
- [ ] Indic scripts are tested with real words, not transliterations.
- [ ] No script is scaled, slanted, or letter-spaced to fit a Latin-shaped box.

## J. Code and system

- [ ] Type, colour, and spacing come from tokens, not one-off values.
- [ ] The scale, rhythm, and grid are documented where the next person will look.
- [ ] Class names describe role, not appearance (`--muted`, not `--grey`).
- [ ] No `!important` used to paper over a specificity problem.
- [ ] Print stylesheet hides navigation and shows link URLs.
- [ ] Fonts are subset, preloaded where they block the first paint, and served as WOFF2.

## K. Measurement quick checks

**Measure.** `max-inline-size` in `ch` is approximate: `ch` is the width of `0`. For most text faces, 60–70 `ch` lands in the 45–75 character range. Verify by counting one full line in the browser.

**Contrast.** Sample the rendered colours, including text over images, disabled states, and dark mode. A passing palette can still fail on a thin weight at 13 px.

**Rhythm.** In devtools, check that paragraph margins, card padding, and section spacing are multiples of the body line height. Break the rhythm only where you can say why.

**Line length.** Resize slowly and watch one paragraph. If the line exceeds the measure or the rag turns into a wedge, the breakpoint is wrong.

**Zoom.** At 200%, the page should reflow like a narrow viewport. Clipped text, overlapping labels, and fixed-height boxes are failures.

## L. Sign-off

A page ships when:

1. The content's extremes fit.
2. The reading order is correct in the DOM.
3. The measure, leading, and rhythm hold at every width.
4. One hierarchy is visible at a glance, and one deliberate exception makes it interesting.
5. It works by keyboard, at 200% zoom, in both colour schemes, and in a screen reader.
6. Nothing on the page exists only because a template put it there.
