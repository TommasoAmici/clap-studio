---
name: designing-websites
description: Design and build websites with deliberate typography, hierarchy, and layout. Use when creating, redesigning, or reviewing a web page or site — choosing typefaces, setting a type scale, measure, and line height, building a CSS grid, composing hierarchy, deliberately breaking the grid, handling responsive reflow, dark mode, accessibility, and right-to-left or multiscript content.
---

# Designing websites

A field guide condensed from Ellen Lupton's *Thinking with Type* (3rd edition) and Timothy Samara's *Making and Breaking the Grid* (3rd edition), translated from print into CSS.

**Core stance:** a website is a reading machine with a point of view. Structure earns trust, typography carries voice, and deliberate irregularity earns attention. A grid is an aid, not a guarantee; no template is a design.

## How to use this skill

Work in this order, and do not skip step 1:

1. **Read the content.** Gather the real text, images, and data, including the longest headline, the shortest caption, and the ugliest table. Layout problems are content problems in disguise.
2. **Name the reading task** for each screen: read, scan, browse, compare, or decide. A page that tries to do all five does none well.
3. **Choose the type system** — one family or a deliberate pair, a scale, a measure, a line height. See [references/typography.md](references/typography.md).
4. **Build the structure** — columns, gutters, margins, rows, zones — before styling components. See [references/layout.md](references/layout.md).
5. **Compose hierarchy** — what the eye meets first, second, third, and what the screen reader hears in the same order.
6. **Break the grid in one or two places** where the content earns it, not everywhere.
7. **Make it reflow** without losing the measure, the rhythm, or the reading order.
8. **Audit** against the numbers and checklist at the end, then look at the page at 320 px, 768 px, 1440 px, and at 200% zoom.

| If the task is… | Start with |
|---|---|
| "Make this page look better" | §1, §5, then the audit |
| Choosing fonts | §2 and [references/typography.md](references/typography.md) |
| Setting type sizes and spacing | §3 and the CSS recipes |
| Laying out a page or app | §4 and [references/layout.md](references/layout.md) |
| A site that feels generic | §6, "Breaking the grid" |
| A site that breaks on mobile | §7 |
| Forms, labels, contrast, alt text | §8 |
| Arabic, Chinese, Japanese, Korean, Indic, African scripts | §9 and [references/scripts.md](references/scripts.md) |

---

## 1. Start with content, not style

Samara's rule: the grid is a **closed system once it is developed**, so account for the content's extremes before drawing it. Build a matrix of page types from simplest to most complex. Anticipate what will break the layout:

- the longest headline, the longest word, the longest URL;
- captions, credits, legal text, and empty states;
- images with different aspect ratios, and images that may not be cropped;
- tables with many columns and long numbers;
- content that runs out — a card with a two-line title beside one with six;
- translated text that grows 30–40%.

An arbitrary grid does a disservice to the content; ill-fitted content deprives the design of expression. Decide the structure from what must be shown, then let the structure make the decisions repeatable.

**Set the reading task.** Lupton's distinction matters: *legibility* is identifying letters and words; *readability* is supporting understanding. Long prose needs a quiet face, a generous measure, and patient spacing. A landing page, a dashboard, and a product grid are scanning tasks: they need stronger contrast in size and weight, shorter blocks, and more obvious anchors.

**Decide what is one thing.** Every screen should have one dominant idea. If two elements compete at the same weight, neither wins.

---

## 2. Choose typefaces

### How many

- **One family** can carry an entire site, especially a superfamily with serif, sans, and optical sizes. This is the reliable default.
- **Two families** work when they divide labour: an expressive display face for headlines and a neutral workhorse for text. Lupton's formula for a poster or campaign — memorable headline face plus "a neutral background player" — applies directly to marketing sites.
- **Three or more** usually means the design has no voice, only options.

Start with the **text face** on a content-heavy site; start with the **headline face** on an identity or campaign site.

### What to look for

Judge a face on objective traits — width and proportion, x-height, the shapes of `a`, `g`, `r`, `y`, ascender and descender length, stress, terminals, serif shape, stroke contrast, spacing, language coverage, number of styles — and on subjective ones: warm or cold, formal or casual, familiar or strange. Both lists are legitimate; naming the traits is what stops the choice from being taste alone.

### Pairing

Contrast alone is not enough. Good pairs share something and differ in something else:

- shared proportions (both narrow, both wide) with different texture;
- shared historical or cultural origin (both grotesques, both humanist);
- shared detail (a similar `a`, similar terminals) with a clear difference in weight or width.

A display face and a text face from the same designer or superfamily is the safest pair. Check the pair at real sizes with real copy, not in a specimen.

### Web constraints that decide the choice

- **Licensing.** Self-host WOFF2 you are allowed to serve. Google Fonts and open licences are fine; desktop licences usually are not. Record the licence next to the files.
- **Language coverage.** A Latin-only face will faux-render or fall back for Vietnamese, Greek, Cyrillic, Arabic, or CJK. Check the actual glyph coverage before promising a locale.
- **Variable fonts** replace a folder of files and allow fluid weight, width, and optical size (`opsz`). Use them, but set explicit `font-variation-settings` only when a named weight will not do.
- **No fakes.** Never let the browser synthesise bold, italic, or small caps. Load the real style, or change the emphasis device. A slanted roman distorts `s` and `o`; shrunken capitals look starved.
- **x-height mismatch.** Two families at the same pixel size do not look the same size. Match x-heights (or cap heights for all-caps settings) optically, not numerically; `font-size-adjust` can help.

| Role | Requirement |
|---|---|
| Body text | True italic, at least regular and bold, sturdy at 16–19 px, good language coverage |
| Headlines | Distinctive shapes, tight spacing that survives at 40 px and above |
| UI labels and buttons | Clear at 12–14 px, unambiguous `1/l/I`, `0/O` |
| Data and tables | Tabular lining numerals, or a separate numeric style |
| Captions and metadata | A text face or its caption cut, not a display face shrunk |

A display face below about 24 px loses its point and often its legibility; a text face blown up to poster size looks clunky. If the family has optical sizes, use them.

---

## 3. Set the type system

### The numbers

| Setting | Default | Notes |
|---|---|---|
| Root size | `100%` (16 px) | Never set a fixed root that blocks user zoom |
| Body size | 16–20 px | 16 px is the floor for prose, not a target |
| Measure | **45–75 characters**, 20–35 `em` | Lupton's range; 50–65 is comfortable for long reading |
| Line height, body | **1.5** | Lupton's screen default; 1.6–1.7 for long-form |
| Line height, headings | 1.0–1.25 | Solid setting for all-caps and large display |
| Paragraph gap | 0.75–1 × line height, **or** a 1 em indent | Never both, and no extra blank line |
| Scale ratio | 1.2 (minor third), 1.25 (major third) | 1.333 for editorial; 1.618 is too dramatic for most systems |
| Spacing unit | 4 px base, 8 px rhythm | Gutters are multiples of the body line height |
| Gutter | ≈ body line height (24 px at 16/24) | Then margins = 2 × gutter |
| Contrast | 4.5:1 body, 3:1 large text and UI | 7:1 for long prose if you can keep it |
| Tap target | 24 × 24 px minimum, 44 × 44 comfortable | WCAG 2.2 minimum is 24 px |

Pick **five to seven sizes** and use them everywhere. A typical set: 14, 16, 20, 25, 31, 39, 49 px — a 1.25 series from 16, plus a 14 px label size. Round values; a scale is a tool, not a religion.

### Measure and reflow

Constrain prose with `max-inline-size` in `ch` or `rem`, never by full viewport width. Text that runs the width of a 27-inch monitor has no measure at all. On a wide screen, let the text block sit asymmetrically with a wide outer margin rather than centring everything — centring hides the structure (Samara).

When the viewport narrows, keep the measure by letting the type size fall and the columns collapse, not by letting lines stretch. Fluid type (`clamp()`) is useful, but clamp both ends: a headline that grows without limit at 4K is a banner, not a headline.

### Alignment

- **Flush left, ragged right** is the default for web text. Word spacing stays even and the rag follows the language.
- **Justified** text needs a long measure, hyphenation, and language-aware settings. On the web it usually produces rivers and holes; use it only when the measure is generous and the language is supported.
- **Centred** text is for short, ceremonial, or single-line content. Long centred paragraphs look mournful and are harder to track back into.
- **Flush right** belongs to right-to-left scripts, captions, and marginal notes. Do not use it for Latin body text.
- Guard the rag: avoid wedges, moons, stairsteps, and a single last word. `text-wrap: pretty` fixes some of this; edit the copy for the rest.

### Vertical rhythm

Set the body line height, then make every other vertical measure a multiple of it: paragraph gaps, card padding, row heights, image heights, gutters, section spacing. A 24 px rhythm with 48 px and 72 px steps produces a page that feels built rather than assembled.

- Use unitless `line-height` so it inherits and scales.
- Avoid fractional results that break the rhythm: `1.15 × 21 px = 24.15 px`, which is not on the 24 px grid.
- Size images and media to whole multiples of the rhythm, or let them define their own aspect ratio and pad around them.
- If a baseline grid is too rigid for a component, align the **first lines** of adjacent columns and let the rest fall organically (Lupton's alternative to a strict baseline grid).

### Details that separate the amateur from the considered

- **Caps and small caps:** letter-space capitals slightly (`0.02–0.08em`); never letter-space lowercase. Use true small caps for abbreviations and labels, not shrunken capitals.
- **Numerals:** tabular lining numerals for tables, prices, timers, and anything that must align; proportional or oldstyle for prose if the face has them.
- **Punctuation:** real quotes (`“ ” ‘ ’`), en dashes for ranges, em dashes for breaks, no spaces around either. Put opening quotes into the margin where the design depends on a crisp edge (`hanging-punctuation`, with a fallback), or accept the small bite.
- **Units and abbreviations:** non-breaking spaces in `10 kg`, `€ 20`, `pp. 4–8`, and between initials.
- **Links and buttons:** underline links in prose, or give them a second cue beyond colour. A button label names the action ("Start free trial"), not "Submit" or "Click here".
- **Decorative type:** a display face is a costume. Wear it for the headline, not for the terms and conditions.

---

## 4. Build the grid

### Anatomy, in web terms

| Print term | Web equivalent |
|---|---|
| Format | Viewport, page shell, container |
| Margins | Page padding, `max-inline-size`, safe areas |
| Live area | Content container |
| Columns | `grid-template-columns` tracks |
| Column gutter | `gap` |
| Flowlines / rows | Row tracks, section boundaries, consistent vertical rhythm |
| Modules | Grid cells, card slots |
| Spatial zones | Named grid areas, regions with different roles |
| Folio / runner | Breadcrumb, section label, sticky nav, footer |

Structure is not decoration: it is the promise that like things sit in like places. The grid is "a visual filing cabinet" (Samara); its junctions are signposts. That is why a site with a weak grid feels untrustworthy even when each component is pretty.

### Choose the grid family

| Grid | Use for | Shape in CSS |
|---|---|---|
| **Manuscript** | A single stream of reading: article, essay, docs page | One column with a max measure |
| **Column** | Editorial pages, marketing sections, mixed text and image blocks | 2–4 columns; blocks span 1–n |
| **Modular** | Dashboards, galleries, catalogues, dense product pages | Columns × rows; cards occupy 1–4 modules |
| **Hierarchic** | Content with genuinely unequal parts: a wide story plus a narrow rail | Unequal tracks (`minmax(0, 2.2fr) minmax(16rem, 1fr)`) |
| **Compound** | A page with two or three different structures sharing margins | Nested grids with shared outer edges |

Rules of thumb:

- **One column** for reading. **Three** for editorial layouts. **Twelve** when components need to span 2, 3, 4, or 6. **Sixteen** for dense, app-like screens (Samara's museum example uses 16 to get 2-, 4-, and 8-module layouts with consistent navigation).
- A column grid stays flexible because narrow columns can always be combined into wider measures. Start narrow; you can merge, but you cannot split.
- Do not add rows you cannot keep. Row structure is the first thing to break when content reflows; align **top edges** of grouped elements, or use background images and consistent card depths.
- **Margin = 2 × gutter** is the printer's default (Samara), and it still works: it makes the column group read as one unit inside its frame. Break it deliberately — narrow margins make a page feel expansive, wide margins make it feel precious.

### Spacing is a hierarchy, not a value

Samara's harmonic ladder, from tightest to loosest:

```
letters < words < lines < paragraphs < gutters < margins
```

Related material sits closer; unrelated material sits farther apart. If the gap between a heading and its paragraph is larger than the gap between paragraphs, the heading floats free (Lupton's "muddled group"). If every gap is equal, separate groups merge into one cluttered field ("uniform spacing" is an error, not a style).

Practical test: squint at the page. You should see the groups before you see the elements.

### Baseline and vertical rhythm

Derive rows from the text, not the other way round:

1. Fix body size and line height (e.g. 16/24).
2. Make gutters and section padding multiples of 24.
3. Make card heights and image heights multiples where possible.
4. If a baseline grid is used, every text style's line height must share a common divisor; captions may land on every second or third line.

Lupton's print example (10/12 body, 18/24 headlines, 14/18 subheads, 8/12 captions) translates directly to a 24 px rhythm. Samara's worked page — eight 48 pt rows with 12 pt gutters in a 570 pt page, leaving 102 pt split 66 head / 36 foot — is the arithmetic to imitate: rows fit exactly, the remainder becomes margins, and the smallest style can hang from the head margin onto the first grid line.

### Don't centre the whole page

Centring the container on the viewport hides the grid: the eye reads the outer shape and stops looking for relationships. Unequal left and right padding, flush-left content, and a visibly asymmetric column split make the structure legible. Symmetry is a valid choice — for ceremony, calm, and formality — but it should be chosen, not defaulted into with `margin-inline: auto`.

---

## 5. Compose hierarchy

Hierarchy is the order in which things are noticed and the order in which they are understood. Those two orders must agree; when they do not, the page lies.

### Visual and semantic

- Use real headings: one `<h1>` per page, `<h2>` for sections, `<h3>` for subsections, no levels skipped for looks.
- Landmarks (`header`, `nav`, `main`, `aside`, `footer`) and lists carry structure for screen readers and search engines.
- Style headings with classes so appearance can change without breaking the outline.
- DOM order is reading order. If the visual order differs, the page must still make sense read linearly.

Lupton's rule: a hierarchy must mark structure **consistently**. The same level gets the same treatment everywhere; a subhead that changes size, weight, and colour from section to section is three subheads pretending to be one.

### Two valid strategies

**Minimal hierarchy** uses one or two sizes and weights, and lets space and position do the work. Egalitarian, calm, editorial. Start with one style, then vary scale, weight, position, or colour — never add a typeface to create hierarchy.

**Layered hierarchy** is the ice-cream sundae (Lupton):

| Layer | Web equivalent |
|---|---|
| Vessel | Page background, container, grid |
| Text | Body copy: comfortable, unremarkable, readable |
| Headline | The loud layer: scale, weight, or a display face |
| Crunchy bits | Labels, small caps, numerals, rules, captions — the texture most sites omit |
| Unique element | Logo, custom lettering, one distinctive graphic move |
| Marginalia | Footnotes, metadata, credits, asides |

Build up in that order. Most weak pages have a vessel and a headline and nothing in between.

### Grouping

Four Gestalt cues, as Lupton uses them:

- **Proximity** — the strongest and cheapest. Space inside a group must be smaller than space between groups.
- **Similarity** — shared colour, shape, size, or orientation groups unlike things.
- **Alignment** — elements on a shared axis read as related ("common fate").
- **Breaking the pattern** — the one element that departs the pattern gets attention. Use it once per screen.

Alignment is a promise: every edge should line up with something. Align images and captions on a shared edge (top, bottom, or side); align columns to a common baseline or cap height; align icons optically, not mathematically. A layout where nothing aligns looks accidental; one where everything aligns looks rigid. Both are choices — make one.

### Emphasis is scarce

One primary action per view. One dominant image or headline. If three things shout, the page is noise. When a secondary action is styled like the primary, users cannot tell what to do (Lupton's exclusive-design example).

---

## 6. Break the grid, on purpose

Samara's warning is the useful one: **"Grids don't make dull layouts — designers do."** The risk runs the other way too: the responsive era has produced "similarly templated, almost interchangeable websites." Clarity and efficiency are not the only goals; some content needs to be felt before it is understood.

### When to break

Break for one of these reasons, and be able to name it:

- **Meaning:** the content is about disruption, speed, multiplicity, or emotion, and a tidy grid would contradict it.
- **Emphasis:** one element must escape the system to become the focal point.
- **Pacing:** a long page needs a change of tempo; the break is a rest or an accent.
- **Narrative:** the layout itself tells the story (a timeline that drifts, a product that grows between sections).

Do not break because the grid is boring. Boredom is a content and hierarchy problem.

### How to break, with the system intact

| Move | What it does | Web implementation |
|---|---|---|
| **Span / breakout** | Lets one element claim more width than its neighbours | `grid-column: 1 / -1`, or a full-bleed child of a constrained parent |
| **Overlap** | Creates depth and new verbal connections | Negative margins, `grid-area` overlap, `z-index` |
| **Scale shift** | Makes one thing disproportionately large or small | A deliberate off-scale `clamp()` value |
| **Off-grid inset** | Signals exception, annotation, or aside | Padding not on the spacing scale, used once |
| **Rotation / diagonal** | Adds energy and a second axis | `rotate()`, skewed rules, diagonal backgrounds — sparingly |
| **Crowding / sparseness** | Changes density to change pace | A dense index beside a nearly empty statement |
| **Collage** | Treats images and type as material | Layered, mixed-media compositions with a clear anchor |
| **Editorial deconstruction** | Lets speech rhythm drive weight, size, and alignment | Variable type, broken phrases, mixed alignment in a headline |
| **Centred-axis structure** | Immediate, formal, monumental | Symmetry with exaggerated scale contrast |

### The constraints that keep it usable

1. **Two or three rules, no more.** Samara: limit the rules and the degree of variation, or the system falls apart. Write them down ("display type may bleed; body text never does").
2. **Keep one strict anchor.** If the headline runs wild, the navigation, captions, and body text must be impeccably aligned. The eye needs a fixed point to measure the deviation against.
3. **Break one axis at a time.** Break the vertical grid or the horizontal rhythm, not both at once.
4. **Do not break the reading order.** Visual order may differ from DOM order only if both remain coherent.
5. **Keep the floor:** contrast, focus states, tap targets, measure, and reflow still apply. Weirdness is not an excuse for an unreadable paragraph.
6. **Cheating is allowed.** A 2–3 px shift to give a heading breathing room, or to make an optical alignment look right, is normal practice — not a failure of the system.

The test: remove the break. If the page loses nothing, it was decoration. If the page loses its point, it was design.

---

## 7. Make it reflow without losing the system

- **Mobile first, structurally.** Samara's method: start from the phone's single column, which is already a legible measure, then repeat and subdivide it for larger screens. A 16-column grid built outward from that base yields 2-, 4-, and 8-module layouts with consistent navigation.
- **Preserve proportions, not pixels.** Breakpoints should change the division of space (halves, thirds, quarters), not just shrink everything. Fluid type, `clamp()`, and container queries keep the relationship between measure, size, and leading.
- **Break where the content breaks,** not at device names. If the measure exceeds 75 characters, or a card's title wraps to four lines, or a table needs horizontal scroll, that is the breakpoint.
- **Use container queries for components.** A card should respond to its slot, not the window; the same card can be wide in a feature row and narrow in a sidebar.
- **Keep reading order linear.** CSS order, `order`, and absolute positioning must not create a visual sequence that the DOM contradicts.
- **Let images keep their ratio.** `aspect-ratio` plus `object-fit`; do not crop faces or data to fill a box.
- **Do not hide content to make a layout fit.** If it matters on desktop, it matters on mobile in some form.
- **Test at 200% zoom and 320 px.** Text must reflow, not clip; horizontal scrolling is a failure for prose.

---

## 8. Inclusive by construction

Lupton's inclusive-design checklist, in web terms:

- Plain language: short sentences, familiar words, concrete examples.
- Persistent labels above fields; never placeholder-only labels. Show the expected format (`DD/MM/YYYY`) before the error.
- Describe errors at the field, in words, and say how to fix them. Never signal error by colour alone.
- Specific link and button text ("Download the sample pack"), not "Click here" or "Read more".
- Alt text for informative images; empty `alt` for decorative ones; captions and transcripts for audio and video.
- Real headings, lists, and table headers; declare the page language (`<html lang="…">`).
- Strong dark/light contrast; never colour as the only carrier of meaning; do not rely on hover alone.
- Visible focus rings, logical tab order, skip links, and keyboard access to every control.
- Respect `prefers-reduced-motion`; avoid autoplay and parallax that cannot be stopped.
- Open-ended form fields where identity is concerned; mark optional fields rather than only marking required ones.

Contrast is a floor, not a style. A palette that passes 4.5:1 can still be unreadable if the type is thin, small, or set over an image; check the actual rendered combination, including dark mode and disabled states.

---

## 9. Multiscript and right-to-left

If the site ships more than Latin, the type system has to be designed for it, not bolted on. The short version is below; [references/scripts.md](references/scripts.md) has the detail for Arabic, Chinese, Korean, Japanese, Indic, and African scripts.

- **Direction:** set `dir="rtl"` on the document or section, use logical properties (`margin-inline`, `padding-inline`, `inset-inline`), and mirror icons that carry direction (arrows, chevrons). Do not mirror logos, clocks, or media controls.
- **Arabic:** right-to-left, cursive, position-dependent letterforms, and optional elongation (*tatweel*) for justification. Use a font with real Arabic, not a fallback. When mixing with Latin, align the Arabic middle line with the Latin baseline (Lupton). Italics have no direct equivalent; use a different weight, style, or colour for emphasis.
- **CJK:** characters are monospaced with no word spaces; a line commonly holds 20–30 characters; body text is usually justified and set with more line spacing than Latin. Align by the character's internal centre of gravity, never by its top or bottom edge. Latin set inside a CJK font often sits too low or too large: check it optically.
- **Korean:** Hangeul is compact and has no ascenders or descenders; it reads shorter and darker than Latin at the same size. Set it slightly smaller with more line spacing, and shift the Latin baseline up so ascenders and descenders match the Hangeul top and bottom.
- **Indic:** many scripts hang from a headstroke rather than sitting on a baseline; conjuncts and matras change the shape and width of a word. Do not force Latin line heights or letter-spacing onto them. Test with real words, not transliterations.
- **Never** fake a script with a Latin font, machine-slant it, or letter-space it to fit a box.

---

## 10. Audit before shipping

Squint, then measure.

**Twelve questions**

1. What is the one thing this page is about, and is it the first thing seen?
2. Does the reading order in the DOM match the visual order?
3. Is the measure between 45 and 75 characters at every width?
4. Is the body at least 16 px, with line height at least 1.5?
5. Do the spaces get larger as relationships get looser (letters < words < lines < paragraphs < gutters < margins)?
6. Does every edge align with something, and is there exactly one deliberate exception?
7. Are there five to seven type sizes, used consistently, or has the page grown a new size per section?
8. Is there one primary action per view, and is the secondary action visibly secondary?
9. Does the page survive 320 px, 768 px, 1440 px, 200% zoom, and long German words?
10. Is every interactive element reachable and visible by keyboard?
11. Does it pass contrast in light and dark mode, including error and disabled states?
12. If you removed the decoration, would the structure still communicate?

**Hard numbers**

| Check | Target |
|---|---|
| Prose measure | 45–75 characters (≈ 60–70 `ch`) |
| Body size | ≥ 16 px |
| Body line height | 1.5–1.7 |
| Heading line height | 1.0–1.25 |
| Type sizes in use | 5–7 |
| Paragraph gap | 0.75–1 × line height |
| Gutter | Multiple of body line height |
| Margin | ≈ 2 × gutter |
| Body contrast | ≥ 4.5:1 |
| Large text / UI contrast | ≥ 3:1 |
| Tap target | ≥ 24 px, ideally 44 px |
| Content width | ≤ 75 characters, never 100% of a wide viewport |

The full checklist, with per-area detail, is in [references/review-checklist.md](references/review-checklist.md).

---

## 11. Anti-patterns

| Pattern | Why it fails | Do instead |
|---|---|---|
| Every section is a centred stack of cards | No structure to read; the page looks like a template | Commit to a grid, then vary spans and zones |
| Body text at 14 px, `#999` on white | Fails contrast and measure; reading is work | 16–19 px, ≥ 4.5:1, max 75 characters |
| Full-width paragraphs on desktop | The eye loses the return to the next line | Constrain the measure; let the margin be empty |
| Type scaled horizontally to fit | Distorts stroke weights | Choose a condensed or extended cut |
| Display face used for body copy | Fatiguing, fragile at small sizes | Display for headlines, text face for prose |
| Faux bold, faux italic, faux small caps | Visible distortion; wrong proportions | Load the real style or change the emphasis |
| Justified text in a narrow column | Rivers and holes | Flush left with a controlled rag |
| Uniform spacing everywhere | Groups merge; the page is a single grey field | Make space inside groups smaller than between them |
| Three competing primary buttons | No hierarchy; the user hesitates | One primary, one secondary, one tertiary at most |
| Centring everything | Hides the grid and the asymmetry that creates energy | Flush-left content, unequal margins where it helps |
| Breaking the grid in every section | Noise; the exceptions stop meaning anything | One or two breaks, anchored by strict alignment |
| Hiding content on mobile | Mobile users get a lesser product | Reflow and prioritise; do not delete |
| Text over a busy image with no scrim | Unreadable at some scroll positions | Contrast layer, or move the text off the image |
| Colour as the only error/status cue | Excludes colour-blind and low-vision users | Add text, icon, or shape |
| Placeholder as label | The label vanishes exactly when it is needed | Persistent label above the field |

---

## 12. This repository's site

`website/` is the worked example of a deliberate break from the neutral template: Swiss structure, punk surface.

- Tokens in `styles.css`: `--paper: #f4f1e8`, `--ink: #191b17`, `--muted: #54574b`, `--line: #d1cec2`, `--hero: #eee95b`, `--pink: #ec52b9`, `--purple: #4622a0`, `--squid: #ff805c`.
- Headlines use Impact with tight tracking (`-.025em`), scaling from `clamp(78px, 8.5vw, 137px)`; body copy is Arial. That split — loud display, quiet text — is the whole system.
- The page frame is `padding: 80px max(5vw, calc((100vw - 1440px) / 2))`, so content never exceeds 1440 px and never touches the edge.
- The `.mono` label style (11 px, uppercase, `0.08em`) is the "crunchy bits" layer; use it for metadata, not for prose.
- Buttons are pill-shaped with a hard offset shadow on hover; focus uses a 3 px outline at 5 px offset. Do not remove the focus ring.
- When adding a section, reuse the tokens and the frame. A redesign may replace the system, but replace it as a system — new tokens, new scale, one deliberate reason — rather than adding a colour or size per section.

The site is due a broader rework (see `ROADMAP/TODO/2026-10-31-website.md`). The expressive sites in that brief are exercises in §6, not an argument to abandon structure: keep the typographic discipline, and let the surface be louder.

---

## Where this comes from

- Ellen Lupton, *Thinking with Type: A Critical Guide for Designers, Writers, Editors, and Students*, 3rd edition — anatomy, typefaces and families, text setting, hierarchy, grids, inclusive design, multiscript.
- Timothy Samara, *Making and Breaking the Grid: A Graphic Design Layout Workshop*, 3rd edition — grid anatomy, building from type and images, vertical rhythm, spatial zones, breaking the grid, usability.

The books are print-first. The translations to CSS, the numeric web defaults, and the audit thresholds are this skill's synthesis. Where the books give a range (Lupton 35–75 characters, Samara 50–80), this skill sets prose at 45–75, the overlap of the two.
