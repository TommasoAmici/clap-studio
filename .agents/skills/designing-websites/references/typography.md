# Typography for the web

Depth behind §2 and §3 of the skill. Everything here comes from Lupton's *Thinking with Type*, 3rd edition, with the print measures translated.

## 1. Anatomy and the em square

- Three horizontal axes govern Latin alignment: **cap line**, **x-line** (median), **baseline**.
- Letter parts worth naming when you diagnose a face: stem, bowl, counter, shoulder, arm, crossbar, spine, tail, terminal, finial, ear, eye, spur, serif, ascender, descender, ligature.
- **Overshoot:** curves pass slightly beyond the baseline and x-line, or they look smaller than the straight letters beside them. This is why mathematical centring of type in a box usually looks wrong.
- The **em square** defines the size: a 16 px font has a 16 px em, though ascenders and descenders may exceed it. Size is therefore a convention, not a measurement of visible height.

**Web consequence:** two fonts at 16 px can look dramatically different in size. Match what the eye sees: x-height for lowercase settings, cap height for all-caps settings. `font-size-adjust` with an `ex-height` value (or `from-font`) is the mechanical version of this correction.

## 2. Height: x-height and optical size

**Large x-height**
- Bigger counters, more open texture, looks larger at the same size.
- Efficient: fits more text in a given area.
- Modern, neutral, screen-friendly. Tends to make a block look denser with the same leading.

**Small x-height**
- More white inside the line, more "lyrical", antique or elegant.
- Less efficient; needs a larger size or more leading for the same comfort.

**Optical sizes.** A family with optical cuts gives sturdier strokes, taller x-heights, and larger counters at small sizes; finer details and tighter spacing at display sizes.

| Cut | Print range | Web range |
|---|---|---|
| Caption / micro | 6–8 pt | 11–13 px |
| Text / regular | 9–14 pt | 15–19 px |
| Subhead | 14–24 pt | 20–32 px |
| Display / headline | 24 pt + | 36 px + |

The one-way rule: caption cuts can be blown up and look exciting; display cuts shrink badly and become frail or blobby. If the family exposes `opsz`, let it track the rendered size (`font-optical-sizing: auto`).

## 3. Width

- **Proportional** is the norm; each letter has its own width plus sidebearings.
- **Monospace** gives every character the same advance. Useful for code, tables of digits, and deliberately mechanical texture; bad for prose, where it wastes space and creates a spotty rhythm.
- **Uniwidth / duplexed** keeps each letter's width constant across weights. Valuable in UI: a button label can change weight on hover without reflowing, and table columns stay put.
- **Never fake width** by scaling type horizontally or vertically. It thins the heavy strokes and thickens the light ones. Use a condensed, compressed, wide, or extended cut.

## 4. Classification

A tool, not a science. Use it to describe what you see and to predict behaviour.

| Category | Traits | Typical use |
|---|---|---|
| **Humanist** (old style) | Moderate contrast, angled stress, calligraphic | Long reading, warmth, authority |
| **Transitional** | Sharper serifs, more vertical axis | Book and editorial text |
| **Modern** (Didone) | Hairline serifs, vertical stress, extreme contrast | Fashion, luxury, display only |
| **Slab** | Serif weight close to the stems | Sturdy headlines, editorial, signage |
| **Humanist sans** | Complex curves, subtle weight variation | UI and body text with warmth |
| **Grotesque sans** | 19th-century proportions, neutral | Interface, corporate, neutral voice |
| **Geometric sans** | Circular `O`, pointed `A/M/N/W` | Modern, architectural, display |

Many faces defy the categories, and vendors now classify by adjective ("rounded", "luxury", "funky"). That is fine for search, useless for reasoning.

## 5. Families and styles

A family shares proportion, stress, contrast, serif shape, cap height, and x-height. A working text family needs at least regular, italic, and bold — **an italic for each weight**, not one italic for the whole family.

- More styles is not better. A large family invites inconsistency; choose the three or four you will actually use.
- Serif families usually offer fewer variations than sans families. Superfamilies (serif + sans + optical sizes) are the most efficient system for a site with both editorial and UI needs.
- **Book** weight (slightly heavier than regular) is the fix for small sizes where regular goes pale.

## 6. Capitals and small capitals

- All caps have no ascenders or descenders, so they sit in a solid, even band. They can take tighter — even negative — leading and read as labels, signage, and authority.
- All caps slow reading for long text: word shapes disappear. Keep them to short labels, headlines, and acronyms.
- **Small caps** are capitals at about x-height. They integrate with lowercase where full caps "disturb the peace", and their square proportions suit subheads, labels, and credits.
- Many fonts lack true small caps and the browser fakes them by shrinking capitals. The result looks starved and too light. Load a font with `smcp`, or do not use small caps.
- Letter-space capitals slightly (`0.02–0.08em`). Never letter-space lowercase; it breaks the word shape.

## 7. Italics

- Italic is a separate design, not a slant. It carries cursive curves, angles, and narrower proportions.
- Sans-serif slanted forms are properly called **oblique**.
- Use italic for titles, foreign phrases, emphasis of a word, and short lyrical passages. Not for long body text: centuries of reading habit make extended italic feel wrong.
- **Faux italic** (a slanted roman) distorts `s` and `o`; it is sometimes hard to spot in a sans, which is not a reason to ship it.
- Alternatives to italic emphasis: a weight change, a colour change, small caps, or a rule. Underlining is acceptable on the web, where it also signals a link — do not use it for emphasis in body copy unless the link style is unmistakable.

## 8. Numerals

|  | Tabular | Proportional |
|---|---|---|
| **Lining** (cap height) | Fixed width; aligns in columns | Kerned; columns ragged |
| **Oldstyle** (ascenders/descenders) | Fixed width; aligns | Kerned; flows with text |

- **Tables, prices, timers, counters, dashboards:** tabular lining. `font-variant-numeric: tabular-nums lining-nums`.
- **Prose:** proportional oldstyle if the face has it, especially in text with many dates or figures; it sits more quietly. `font-variant-numeric: oldstyle-nums proportional-nums`.
- **All caps:** lining numerals. Oldstyle figures among capitals look like lowercase intruders.
- Superscripts and fractions should come from the font (`font-variant-position`, `font-variant-numeric: diagonal-fractions`), not from `<sup>` with a shrunken size.

## 9. Punctuation

| Mark | Name | Correct use |
|---|---|---|
| `-` | hyphen | Compound words, line breaks |
| `–` | en dash | Ranges: 2018–2026, 5–7 years |
| `—` | em dash | A break in thought; replaces commas, colons, parentheses |
| `' "` | prime marks | Feet and inches: 5′2″ |
| `'` | apostrophe | Contractions and possessives |
| `“ ”` | curly quotes | Quotation, titles of short works |

- No spaces around en or em dashes. Use one or the other consistently.
- Quotation marks differ by language: double in US English, single in UK English, guillemets in French, Italian, Portuguese, German, Danish (pointing inward in German and Danish). Do not "correct" a locale's punctuation into your own.
- **Hanging punctuation:** opening quotes pushed into the margin keep the left edge crisp. `hanging-punctuation: first` works in some browsers; elsewhere use a negative text indent on the block or accept the gap.
- **Inclusive punctuation:** the German gender star (*Fahrer*innen*) and French *les candidat(e)s* are live conventions. Do not silently normalise them away.
- Ellipses: the single glyph `…`, not three periods. Non-breaking space after short prepositions and before units where the language requires it.

## 10. Variable fonts

One file, a continuous range. The five registered axes:

| Axis | CSS | Use |
|---|---|---|
| `wght` | `font-weight` | Weight; the most common axis |
| `wdth` | `font-stretch` | Width; useful for responsive headlines |
| `ital` | `font-style: italic` | Italic |
| `slnt` | `font-style: oblique <angle>` | Slant without a separate italic |
| `opsz` | `font-optical-sizing` | Automatic optical correction |

- Named instances map to ordinary weights (100–900) and are what you should usually request.
- Custom axes (gravity, softness, "year") are expressive; use them where the design can carry the motion, not in body text.
- A variable font is not automatically faster: subset it, and do not ship axes you never vary.
- Animate weight or width only if the change carries meaning, and respect `prefers-reduced-motion`.

## 11. Choosing and pairing

**Start from the job:**

| Site | Start with | Because |
|---|---|---|
| Blog, docs, long-form | Text face | Most of the page is reading |
| Campaign, launch, identity | Headline face | Voice is the product |
| Product UI | Neutral UI face + one expressive accent | Legibility under repetition |
| Data-heavy | Face with tabular figures and clear `1/l/I` | Misreading numbers is expensive |

**Objective checklist:** width, proportion, x-height, `a`/`g`/`r`/`y` shapes, ascender and descender length, stress, terminals, serif shape, stroke contrast, spacing, authorship, historical origin, language support, number of styles.

**Subjective checklist:** cold or warm, formal or casual, emotional register, memory, craft, previous uses, trend value, taste.

**Pairing rules:**

- Share one thing (proportion, origin, terminal shape, x-height), differ in another (weight, width, texture).
- Contrast without kinship reads as an accident.
- Test the pair in the real sizes and the real copy; a specimen sheet lies.
- A superfamily is not a compromise; it is a system.

## 12. Setting text

### Leading and line height

- Print default was 120% of the size; screen default is **1.5** (Lupton). Both are starting points.
- Longer measures take a little more leading; headlines take less.
- Whole-number relationships matter more than exact percentages: if body is 16/24, make other styles land on multiples of 24 where possible.
- Auto leading breaks when sizes are combined: a heading can end up with more space inside it than after it. Set line heights explicitly.
- Reversed text (light on dark) benefits from slightly more leading and, often, a slightly heavier weight.

### Measure

- **45–75 characters**, or 20–35 `em`, for prose.
- Ruder: 50–60. Bringhurst: 45–75. Samara: 50–80 including spaces, about 8–12 words.
- Too long: the eye loses the return. Too short: the eye jumps constantly and the rag or justification breaks down.
- Implement as `max-inline-size: 65ch` (or `34rem`), not as a percentage of the viewport.

### Alignment

| Mode | Behaviour | Use |
|---|---|---|
| Flush left | Even word spacing, live rag | Default for web prose |
| Justified | Even edges, variable word/letter spacing | Long measure, hyphenation, print-like editorial |
| Centred | Breaks into phrases, fluid outline | Short, ceremonial, single lines |
| Flush right | Hard right edge | RTL scripts, captions, marginalia |

- A rag is bad when it is too even (looks like a mistake), too uneven (creates shapes), or forms wedges, moons, stairsteps, or diving boards.
- Justification depends on hyphenation and a long measure. In a narrow column it produces rivers — chains of word spaces running down the paragraph.
- Optical margin alignment: let punctuation and quotes hang slightly outside the measure to sharpen the edge.

### Paragraphs

- Mark a new paragraph with **either** a first-line indent (**1 em**) **or** a space (about 0.75–1 line), not both, and not both plus a line break.
- Never indent the first line of a text or the first line after a heading: the indent signals a break that has already happened.
- On the web, the browser default margin around `<p>` is usually too large and too even; set it explicitly.
- Hanging indents (outdents) need a wider gutter or careful spacing from the preceding column.

### Kerning and tracking

- **Kerning** adjusts a pair; **tracking** adjusts a run of letters.
- Text sizes rarely need manual kerning if the font is well made. Headlines do: gaps become visible as size grows.
- Metric kerning for text, optical kerning for display, manual adjustment for stubborn pairs (`LA`, `To`, `Tr`, `Ta`, `Tu`, `Te`, `Ty`, `Wa`, `We`, `Wo`, `Ya`, `Yo`).
- Positive tracking on capitals or small caps can be elegant; on lowercase and italic it usually looks awkward.
- Negative tracking on a large headline tightens it and adds emphasis; keep it subtle in body text, where it overrides the designer's spacing.
- Reversed text: +20 tracking improves readability.
- On the web, use `letter-spacing` in `em` so it scales, and `font-kerning: normal`.

### Short lines and bad breaks

- A single word on the last line of a paragraph is a **short line** (the older terms widow and orphan are needlessly gendered; avoid them).
- Fix by editing the copy, adjusting the measure, or using `text-wrap: pretty`. Do not chase every short line: automated layout and user font settings make some inevitable.
- `text-wrap: balance` for headlines (a few lines), `text-wrap: pretty` for paragraphs. Neither replaces editing.

## 13. Legibility versus readability

- **Legibility:** can the reader identify the letters? Depends on x-height, counter size, spacing, character width, and differentiation (`I/l/1`, `O/0`, `B/8`, `p/q`).
- **Readability:** can the reader understand the text? Depends on line spacing, measure, hierarchy, and the design of the letterforms.

They are not the same, and neither is purely a property of the font. Familiarity, ability, context, and purpose all shape performance. A wide letter is more legible in isolation but fits fewer characters, so it may be less readable at the same physical size. A highly differentiated face (Atkinson Hyperlegible) helps some readers and creates a spottier texture for others. Helvetica's uniformity is exactly what makes it hard for a reader who confuses `B` and `8`.

Serif versus sans is not settled by evidence: research has failed to prove that serifs improve reading speed or comprehension. Choose by context, texture, and voice, and prefer familiarity for long text.

## 14. Writing is part of typography

Lupton is blunt: "Typographic beauty can't fix dull writing."

- Prefer concrete nouns and strong verbs. "Airports, parks, sidewalks" beats "public spaces".
- Put the actor and the action early. Passive, abstract constructions hide both.
- Cut the throat-clearing: "It has proved difficult to validate through research that…" → "Research has failed to prove that…"
- A headline should stir curiosity or imply an action, not merely label the section.
- Hostile prose — jargon, pointless detail, unfamiliar words — is a design failure before it is a typographic one.

## 15. Type scales

Start from **16 px** on the web and multiply by a ratio:

| Ratio | Series from 16 |
|---|---|
| 1.125 (major second) | 16, 18, 20.25, 22.8, 25.6, 28.8 |
| 1.2 (minor third) | 16, 19.2, 23, 27.6, 33.2, 39.8 |
| 1.25 (major third) | 16, 20, 25, 31.25, 39, 48.8 |
| 1.333 (perfect fourth) | 16, 21.3, 28.4, 37.9, 50.5 |
| 1.5 (perfect fifth) | 16, 24, 36, 54, 81 |
| 1.618 (golden) | 16, 25.9, 41.9, 67.8 |

- Golden-ratio jumps are too dramatic for most systems; 1.2–1.333 is the useful band.
- Round to whole pixels or to a consistent fractional scheme; do not mix.
- A scale can feel limiting when families have very different proportions; adjust optically, not arithmetically.
- Historical print sizes rose by one point to 12, then in larger steps — a reminder that differences should be perceptible: one-point steps matter at small sizes, not at large ones.
- Pick five to seven sizes and assign roles: micro, caption, body, lead, h2, h1, display.

## 16. Vertical text

Chinese and Japanese read vertically or horizontally; square forms make handsome columns. Stacked Latin suits headlines and narrow spaces, but it has rules:

- **Uppercase stacks are more stable than lowercase**, whose ascenders, descenders, and varied widths make the column wobble.
- **Centre** the stack to compensate for width differences, or set it flush to one edge as a deliberate choice.
- Monospace stacks well because every character has the same width; slab serifs widen a skinny `I`.
- **Rotating 90°** preserves the natural affinity of letters on a line but is harder to read; use it for short labels, not prose.
- Purpose-built families add vertical kerning and ligatures.

```css
.vertical {
  writing-mode: vertical-rl;
  text-orientation: mixed; /* keeps CJK upright, rotates Latin */
}

.tate-chu-yoko {
  text-combine-upright: all; /* two or three digits or Latin letters upright in a vertical line */
}
```

## 17. Ornament, texture, and lettering

Ornaments do not represent language. Rules and straight lines frame and divide; decorative sets can be assembled into patterns; layered typefaces and **colour fonts** produce outlines, inlines, and shadows from one family.

- On the web, ornament is `border`, `::before`, SVG, or a background pattern. It should **amplify structure**, not compete with it — Lupton calls ornament "visual surplus" that can distract.
- A rule that separates two groups is structure. A rule that underlines every heading is decoration. Know which you are adding.
- **Lettering** is custom drawing, by hand or in software, that can emulate type or melt text into an image. On the web it belongs in SVG, a logo, or a hero graphic — not in body copy, where it cannot reflow or be read by a screen reader.
- Texture from type (overlapping, layered, cropped) is a legitimate expressive device for a poster-like section. Keep an accessible text layer underneath, and never set essential information in an image of type.
