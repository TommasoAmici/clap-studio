# Layout and grids for the web

Depth behind §4–§7 of the skill. Drawn from Samara's *Making and Breaking the Grid*, 3rd edition, and the layout chapters of Lupton's *Thinking with Type*, 3rd edition.

## 1. What layout is for

A layout arranges elements so the eye knows where to start, what belongs together, and what matters. Lupton's recurring principles: **balance, alignment, hierarchy, white space, framing, grids**. Samara's three benefits of structure: **clarity, efficiency, continuity** — decisions made once, many hands able to work without diluting the result.

The grid is an orthogonal system that parcels information into manageable chunks. Its junctions act as signposts; like things in like places make similarities visible. It is "a visual filing cabinet", not a moral position.

Three cautions worth keeping:

- Müller-Brockmann: "The grid system is an aid, not a guarantee… one must learn how to use the grid; it is an art that requires practice."
- Vignelli: the grid is a lion in a cage; the designer is the tamer, and must know when to get out.
- McCoy: society needs "subtlety, complexity, and contradiction", not only simplicity.

Samara's diagnosis of the responsive era: grids are now so easy that the result is often "similarly templated, almost interchangeable websites". Efficiency is real, and so is the cost.

## 2. Scaffolds, balance, framing

### Symmetry and asymmetry

| | Symmetry | Asymmetry |
|---|---|---|
| Device | Borders and margins act as a frame | Grid lines structure from the inside |
| Effect | Stable, direct, centred, formal | Active, charged, less obvious |
| Web use | Ceremonial pages, single statements, classic editorial | Most content sites, dashboards, editorial with a rail |

Both can coexist — a symmetric page with one asymmetric content block, or the reverse. What fails is drifting between them: an almost-centred layout looks like a mistake.

### The frame

Margins are not leftover space. They are the frame that separates content from the world, focuses the eye, and gives the composition status. Lupton quotes Derrida on the frame that "disappears, buries itself, effaces itself" even as it does its work. Borders and rules do the same job more explicitly.

On the web the frame is viewport padding plus a maximum content width. Two consequences:

- A page with no maximum is not framed at all on a wide monitor; the eye has no edge to measure against.
- A page with too generous a frame on a small screen wastes the only space it has.

### White space as an object

Treat empty space as shaped, not absent. Dwiggins described text as "a peninsula of letterpress" reaching into "the paper ocean", with bays and promontories that should be emphatic. In CSS this means thinking in terms of the negative shapes between cards, not only the cards.

Samara: "A grid organizes space as much as it does the stuff that's in it." White space participates in a part-to-whole relationship with the content.

## 3. Grid anatomy

| Part | Definition | Web mapping |
|---|---|---|
| Format | The page or screen and its proportion | Viewport, page shell |
| Margins | Space between format edge and live area | Page padding, safe areas |
| Live area / body | The structured area inside the margins | Content container |
| Columns | Vertical alignments of type | Grid tracks |
| Column gutter | Channel between columns | `column-gap` |
| Flowlines | Horizontal divisions that break vertical space into bands | Row tracks, section boundaries |
| Rows / row gutters | Repeated flowlines, creating a counterpoint | Row tracks and `row-gap` |
| Modules | Units formed by column × row intersections | Cells, card slots |
| Spatial zones | Groups of columns, rows, or modules with assigned roles | Named grid areas |
| Foredge | Outer edge | Inline end |
| Gutter (binding) | Channel at the spine | No direct equivalent; scroll position and sticky elements take over |
| Folio / runner | Page number and running head | Breadcrumb, section label, sticky nav |

**Mirrored** structures place the body symmetrically; **offset** structures shift it, producing unequal margins. On screen there is no facing page, so "mirrored" becomes a choice about symmetry, not a physical necessity.

**Notation matters.** Folios and runners sit in the same place on every page so readers can find them; they need separation and often widen the margins. On the web the sticky header, breadcrumb, and footer do this work. They are part of the grid, not chrome bolted on afterwards.

## 4. The five grid families

### Manuscript (block)

One large text block per page, with margins. Use for long continuous reading: articles, essays, documentation. It reads as historical, authoritative, institutional — useful or contrary depending on the brief.

- In print the unit is the spread, not the page. In CSS the unit is one measure-limited column.
- Variation comes from margin proportion, not from adding columns.
- A single flowline can separate a title block from the body.

### Column

Two or more vertical zones. The workhorse: flexible, familiar, teachable.

- Columns may run together, stand alone, or combine into wider measures. Images and text chunks may sit at any depth top-to-bottom, but their widths must correspond **edge to edge** to one or more columns.
- Three columns is the classic editorial default. Eight to twelve appears in newspapers, magazines, and app shells.
- Narrower columns can always be combined to look wider. This is why starting narrow is safer than starting wide.
- Add flowlines only where a horizontal constant is genuinely needed.

### Modular

Columns plus repeated rows produce a matrix of modules. Use when many kinds of information coexist: dashboards, catalogues, galleries, dense product pages.

- Grouped modules make larger proportional chunks and **spatial zones**.
- Smaller modules buy flexibility and precision, but too many subdivisions become confusing or redundant.
- Samara notates them `C# × R#` (columns by rows).
- A graph-paper variant has no gutters; the module itself is small enough to read as one.

### Hierarchic

Custom column widths and intervals derived from the content's own proportions, not a regular interval. Use when the parts are genuinely unequal: a wide story plus a narrow rail, a hero plus a caption strip.

- Column widths and gaps vary by context.
- Rows may exist in only one part of the format.
- It still holds together through clear orthogonal relationships; "hierarchic" is not a licence for misalignment.
- Common on websites whose content depth and width vary.

### Compound

Two or more grids in one project or page. Three patterns:

1. Two or more grids sharing outer margins, with internal alignments that may or may not correspond.
2. Grids overlaid with independent margins.
3. Grids separated spatially — three columns above for primary content, five below for captions.

Use sparingly: a compound grid is a promise that the parts relate. If they do not, it reads as two pages stapled together.

## 5. Building a grid from type

The type creates the grid before any lines are drawn: stems make words, words make lines, stacked lines make columns, adjacent columns make a horizontal structure.

### Size

No universal point size exists, because x-heights differ. Samara's method: compare every face to **Times Roman at 9 pt** and adjust until lowercase heights match, even at a non-round number. Condensed faces have smaller counters: enlarge slightly and track more loosely.

### Measure

**50–80 characters including spaces**, roughly **8–12 words**, before a line return. Within that range:

- hyphens drop;
- the rag becomes rhythmically regular;
- justified text avoids dark and light patches and rivers.

This count fixes the paragraph width for that face at that size. It is the single most useful constraint in the whole system.

### Leading

Interline space should be larger than the apparent lowercase height, but not pronounced. It must:

- keep descenders off the next line's ascenders;
- let the reader find the start of the next line after a return;
- change as the measure moves away from the optimum — longer lines need more air.

### Deriving columns

1. Set specimens of every text style, flush left, in a vertical stack.
2. Mark the left edge and the longest line of each.
3. Look for fractional relationships: a caption width that is 1/2 or 1/3 of the running text.
4. Combine the fractions into one **universal width increment** — a proto-column — of which every width is a multiple.
5. Accept small deviations from each style's ideal width; the character-count range has tolerance.

Running text matters most: it appears in the greatest volume and is the hardest to read.

### Deriving gutters

Derive them from the running text so the eye travels **down** a column rather than sideways into the next one. Then fit as many columns-plus-gutters as possible into the format; the remainder becomes the inner and outer margins.

### Deriving rows

Baseline alignment across columns is optional — historically desirable, subjectively chosen. Two paths:

**Without a baseline grid:** choose a row depth interval, a row gutter, a row count, and head and foot margins. Faster, looser, fine for most web layouts.

**With a baseline grid:** adjust every style's leading until all share a **common divisor** (multiples of 6, for example; this book uses multiples of 2.1). Find the interval where most baselines coincide, set the row depth there, set the row gutter from the running-text leading or another multiple, fit the rows, and split the remainder into head and foot margins.

Caveat: changing leading to serve the grid can spoil previously optimal interline spacing. Extra leading is usually tolerable; less is not.

### Worked example (print, translatable)

- Page height: 570 pt.
- Common leading: 6 pt.
- Row depth: 48 pt; row gutter: 12 pt.
- Eight rows = 468 pt.
- Remainder: 102 pt, split 66 pt head / 36 pt foot.
- Baseline grid begins 72 pt from the top, so a 6 pt caption can hang from the head margin onto the first grid line.

The arithmetic is the lesson: rows fit exactly, the remainder becomes margins, and the smallest style can land on the first line. In CSS, the same logic becomes a spacing scale and a `line-height` that divides evenly into row heights.

### Harmonic spacing

The printer's rule: **margin = 2 × column gutter**, so the column group holds together as one unit inside its frame. Generalise it into a ladder:

```
letters < words < lines < paragraphs < column gutters < margins
```

Contiguous or related material sits closer; unrelated material sits farther apart. If the ladder is inverted anywhere — a paragraph gap larger than a section gap, a gutter wider than a margin — the page reads as disordered even when every element is well set.

## 6. Building a grid from images

- If all images share an aspect ratio, make that the **module proportion**, then build columns and rows from it; type inherits the same logic.
- Keep or change margins per format; add or remove module columns and rows; scale the whole module group down for dense pages or up for posters.
- A square image confronting a wide format produces different secondary breaks, hence a different grid. Proportion alone can create tension.
- With no-crop rules and mixed ratios: compare the ratios, find fractional relations by scaling, distil a module that accommodates all of them plus gutters, then slide the module group until the margins feel right.

## 7. Grids for interaction

- **Start from the phone.** Its width is already a column that holds legible type. Repeat that column for larger screens; subdivide the base column for finer structures.
- A **16-column** grid yields 2-, 4-, and 8-module permutations with consistently sized and spaced navigation — conditions you can only reach by building outward from the smallest screen.
- **Breakpoints** control field division and readability as the browser collapses. Alternatively, preserve the *logic* of division (half of half of half) rather than exact widths.
- **Centring** the content on the viewport obscures the grid: symmetric rags defeat alignment reading and the eye sees only the outer shape.
- **Unequal left and right padding** calls attention to the difference and makes the eye seek corroborating relationships. Exaggerate position and insist on flush-left.
- Preserve **relative proportions**, not absolute widths, as the browser resizes.
- Padding is either **zero** (cells align to columns) or **consistent and summing to the gutter measure**.
- Row structure is nearly impossible to enforce across reflow. Align **top edges** of grouped elements, or use background images with comparable depth proportions.
- Navigation: anchor wide link groups to a major content alignment; align each link to a column edge; or shift the group fully off-alignment while preserving column-width spaces; or abandon the horizontal header for a vertical navigation column.
- Template defaults create two recurring conflicts: symmetry versus asymmetry, and wide horizontal versus narrow vertical fields.

Structure carries meaning: symmetry reads classical and authoritative; asymmetry reads modern and casual; horizon lines pull the eye "groundward"; quadrants evoke seasons; low-set grids evoke cityscapes.

## 8. Using a grid

### Articulation

From rigid to organic:

1. Material **justified to margins or module depths** — rigid geometry.
2. Material **hanging** from a common line — consistent with changing depth.
3. Material that **changes hangline and depth** — most organic and flexible.

Body position is a separate decision: mirrored or offset, inward or pushed to the foredges. A **false margin** — an unused grid column — can be reclaimed when needed. An empty column on an opening spread can make an article start asymmetrically, then symmetrically, signalling sequence.

### Fullness

"A little mystery — leaving columns or modules open, not revealing the structure at every juncture — goes a long way." Full-to-margins pages become texture; open modules create movement; pushing content to the exterior leaves an undefined open field.

### Depth versus surface

- Fuller page + more marked alignments + similar element sizes + large text masses = **flat**, surface activity.
- More open modules, varied negative shapes, strong size contrasts = **deep**, elements floating as objects.
- Transparency and layered media make depth ambiguous; use that deliberately.

### Variation and violation

"The greatest danger in using a grid is to succumb to its regularity… Grids don't make dull layouts — designers do."

Named techniques:

- Alternate spatial zones page to page (horizontal emphasis, then vertical) for interest and unity.
- **Bounce:** cluster images at the top on one spread, the bottom on the next; reuse the same small, medium, and large sizes in new positions.
- Articulate different column structures while keeping one positioning logic.
- Violate with a secondary structure — diagonal channels based on the row measure, irregular illustrative forms.
- Let letterforms deviate within modules, extend beyond them, or be cropped by them, anchored by one strictly aligned small text element.
- Occasionally ignore the grid entirely for pacing and emphasis.
- Design transgression into the structure: elements crossing gutters, pushing past margins, intruding into text fields.
- **Cheat:** shift elements slightly off true alignment for breathing room. "Cheating in this way happens in every designer's work — and it's OK."

### Pacing

"Ordering is about function; pacing is about feeling." Vary slow and fast, quiet and dynamic, to re-engage the viewer and cue a change of content. On scrolling pages, pacing is lateral position plus changes in mass, depth, and width.

### Formats and media

Derive every touchpoint from one column or module proportion: cohesion, harmonious joint use, simultaneous production, lower cost. Samara's museum example derives the grid from a logo of three squares, extends it into strips, banners, kiosks, and a four-column web structure with navigation outside the grid.

## 9. Grouping and alignment

### Gestalt, as Lupton presents it

- **Proximity:** the distance between elements establishes relationships. The space between a headline and its text must be smaller than the space between paragraphs; otherwise the headline floats free.
- **Similarity:** colour, shape, orientation, and value group elements; use them to emphasise or downplay.
- **Alignment / common fate:** elements on a shared axis read as following a shared path.
- **Breaking the pattern:** the exception attracts the eye. Ungroup an element by changing its colour, weight, or size.
- **Uniform spacing is an error:** equal spacing everywhere causes separate groups to merge into one cluttered field.

Weight and line spacing also govern unity: heavier type and larger line spaces emphasise individual letters and lines; lighter text and tighter spacing create an even texture and a coherent block.

### Alignment in practice

Because letterforms are irregular, alignment is not automatic. Horizontal options: cap height to cap height, x-height to x-height, baseline to baseline. Vertical options: column edge to column edge, or a prominent letterform's edge.

- Align a caption to its image on a shared edge (top, bottom, or side); the choice changes the relationship.
- Align interface components and marginalia to the same axes as the content, or they read as debris.
- **Type as scaffold:** at large scale, letterforms divide the space and create implied grids; the letters, not a preordained grid, become the armature.
- **Optical centring:** lowercase text in a box must be centred by eye, because ascenders and descenders make mathematical centring look wrong.
- **Bullets and opening quotes hang left** of the alignment; otherwise the aligned edge looks sloppy.
- Initial caps and callouts that invade text should either correspond to grid increments or clearly not conform — the ambiguous middle looks like an accident.
- Paragraph breaks need not fall on row guides; forcing them produces awkward separations and self-conscious typography.

### Borders and rules

Borders focus the eye and gather content into groups. Like grids they define large areas or break space into smaller chunks. Layer, overlap, and divide framed areas to imply motion and depth. Text inside a box needs breathing room: extend the box to the gutters, inset the text, or both, with inside and outside text aligning consistently.

## 10. Breaking the grid

### The argument

A grid is a convention suited to particular goals. Imposing one "may, in fact, compromise the information's integrity". Some content has an internal structure that must be upheld; some must ignore structure to produce emotion or association; some needs greater intellectual involvement to resonate.

History's counter-lineage, condensed: Asian layout that fills the page and hierarchies by colour, size, and weight; Islamic calligraphy whose ascenders and diacritics resist compact blocks and whose recitation invites exaggeration; European runestones, shaped poems, instructional diagrams; Art Nouveau organicism; Cubist deconstruction; concrete poetry; Futurist and Dada typography; Basel's "other International Style" (Ruder, Weingart) that mixed weights, slants, and sizes within a line; Cranbrook and the deconstruction of the 1980s; desktop publishing and Carson's overlapping, reversed, densely textured pages.

The useful conclusion is not "grids are bad" or "grids are good". It is that **rational structure is one of many possible systems, and context decides**.

### Alternative architectures

| Strategy | Method | Effect and caution |
|---|---|---|
| **Slitting, splicing, shifting** | Install a base grid, separate columns or rows at irregular intervals, cut across and slide the parts | New axes and alignments; displaced information creates new verbal connections. Foreground and background can swap. |
| **Deformation / distortion** | Pull column and row edges out of parallel; make them angular or curvilinear | Diagonal axes and illusory perspective. Curvilinear columns can still read as columns, preserving parseability. |
| **Verbal / editorial deconstruction** | Let speech rhythm drive weight, size, colour, alignment; treat a part of speech consistently; break phrases and words | Creates a secondary organic structure; changes reading order. Interferes with reading — acceptable only when ambiguity serves the content. |
| **Centred-axis structure** | One governing axis, buried in the material; bilateral or rotational symmetry | Immediate, direct, formally simple; the group reads as one shape. Unforgiving: off-axis elements look disunified, and viewers reach "intellectual rest" quickly. Exaggerate contrasts; let oversized forms press against the format. |
| **Other geometric systems** | Musical intervals (A/B/A, A/B/A/C), numeric ratios (1:3:5:7), Fibonacci (1:1:2:3:5:8:13:21:34) | Any progression can generate divisions. The Golden Section is "counterintuitively organic": its leftovers do not read as tidy fractions. |
| **Non-orthogonal families** | Arcing, branching, chaining, clustering, concentric, constellational, diagonal, framed, networked, radial, resting, rotational, spiralling, stacking, staggering, stepping, wave | Each carries an association; they can be combined. |

### Intuitive, relational, conceptual

- **Spontaneous composition:** place by eye, fast and loose, adjusting as optical qualities interact. Collage is its closest relative. Contrast is crucial — size, spacing, density, value, geometry versus organic, flat versus volumetric.
- **Imagery as source:** either type becomes part of the imagery, or imagery sets the logic while type keeps its identity.
- **Narrative constructs:** pictorialisation (the layout looks like its subject), metaphor, allusion (spliced repeated images read as film editing; layered posters read as street posting).
- **Vernacularism:** borrow the everyday — a receipt, a contract, supermarket lettering — and let the comparison do the work.
- **Chance:** random physical operations (flung paint, dropped clippings) or programmatic ones (arbitrary grid dissection, timed capture, overprinting then deleting overlaps). Chance surfaces juxtapositions that structured thinking misses.
- **Systematising the organic:** ask what the prevalent conditions are — what images, whether geometry matters, what creates depth, what kind of movement. Those answers are the rules. **Limit the rules to two or three**, limit the number and degree of variations, and apply them consistently. A discrepancy is either edited out or becomes a new rule.

## 11. Reconciling usability and weirdness

Samara refuses the premise that usability precludes invention: "why deny the potential of an unusual solution for the reason that it's not functional… Yet?"

Two things cause most navigation trouble:

1. **Optical differentiation.** Bigger and bolder reads first; push the differences further than feels necessary. Repeating obscured information can help or confuse; better to give it room where it appears in sequence. "When in doubt, simplify."
2. **Eye path.** For Western readers, orient top-level elements toward the left; make the next elements differ similarly or sit where the eye leaves the first; insert markers and anchors. The eye moves from greatest to least **optical resistance** along axes the designer supplies.

Contrast in **size and spacing** is the strongest hierarchy tool; hue and value amplify it; **repetition** assigns relation regardless of position.

Dissonance-reduction tactics: apply macro composition gestures at micro scale; use subheads and callouts as a bridge; make crisp rectangular images share the surrounding visual characteristics; recast data into a chart shape that matches the layout, or rotate a table slightly — never compromising data integrity.

Interaction without grids: content first; navigation clearly distinct from content; legible text; intuitive flow; a traceable sequence; any screen reachable from anywhere; fast load; and "it must be a beautiful, compelling experience worthy of their time."

Web-specific breakers: parallax (different scroll rates inherently break row alignment), forced text deviations (misalign column divisions between cell sets, vary padding per side, set type as image), false image proportions (transparency, silhouettes, collaged images, background images).

## 12. Serial design and components

A site is a series, not a page. Serial design applies one typographic hierarchy across many pages, posts, and components so that the family resemblance is unmistakable while each item can still stand on its own.

- Websites and digital products are built from **modular components**, each containing "the DNA of the overall system" (Lupton). A card is the clearest example: a fixed set of slots, a consistent type hierarchy, and enough flexibility for one-line and six-line content.
- Cards can be rearranged and resized across viewports; a card design can become the prototype for larger sections.
- A consistent template helps users find and compare; variation inside the template is what stops the catalogue from becoming wallpaper.
- Develop the system in **light and dark themes** at the same time. A component that only works on one background is half-designed.
- A single family can be "surprisingly rich": the Chicago Architecture Biennial site puts its identity into event boxes with distinctive borders and an array of type styles and sizes.
- Piet Zwart's 1920s catalogues are each unique yet express a common identity — the model for a design system that is a language, not a locked template.

In CSS terms: tokens for type, colour, and spacing; named components; a small number of variants (`--feature`, `--compact`); and a documented rule about when a variant is allowed. If every page re-decides its type sizes, there is no series.

## 13. Print assumptions to translate

| Print | Web |
|---|---|
| Spread, spine, facing pages, inside/outside margins | No fixed pair of pages; padding, max-width, safe areas |
| Parent pages, page-size dialogue | Components, templates, container queries |
| Points, picas, fixed page dimensions | `px`, `rem`, `em`, `ch`, fluid scales |
| Fixed column counts and gutters | Responsive tracks; counts change at breakpoints |
| Baseline grid in layout preferences | `line-height`, a spacing scale, row heights |
| Halftone blocks in fixed sizes | `aspect-ratio`, `object-fit`, responsive images |
| Letterpress rules and ornaments | Borders, pseudo-elements, SVG |
| PDF article order, XML tags | DOM order, landmarks, heading structure |
| Paper stock, bleed, signatures | No equivalent; do not simulate production constraints |
