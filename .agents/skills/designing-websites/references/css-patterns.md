# CSS patterns

Working recipes for the decisions in the skill. Values are starting points; change them with a reason.

## 1. Tokens

```css
:root {
  color-scheme: light dark;

  /* Type */
  --font-text: "Source Serif 4", Georgia, serif;
  --font-ui: "Inter", system-ui, sans-serif;
  --font-display: "Inter Tight", "Inter", system-ui, sans-serif;
  --font-mono: ui-monospace, "SFMono-Regular", Consolas, monospace;

  /* Scale: 1.25 from 16px, rounded */
  --text-xs: 0.75rem;   /* 12 */
  --text-sm: 0.875rem;  /* 14 */
  --text-base: 1rem;    /* 16 */
  --text-lg: 1.25rem;   /* 20 */
  --text-xl: 1.5625rem; /* 25 */
  --text-2xl: 1.9375rem;/* 31 */
  --text-3xl: 2.4375rem;/* 39 */
  --text-4xl: 3.0625rem;/* 49 */

  /* Vertical rhythm: body 16/24 */
  --leading: 1.5rem;
  --leading-tight: 1.15;

  /* Spacing: multiples of the rhythm */
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-6: 1.5rem;
  --space-8: 2rem;
  --space-12: 3rem;
  --space-16: 4rem;

  /* Frame: gutter 24, margin 2× gutter */
  --gutter: 1.5rem;
  --page-margin: clamp(1.25rem, 5vw, 4rem);
  --measure: 65ch;
  --content-max: 72rem;
}
```

One scale, one rhythm, one frame. A page with two spacing systems has none.

## 2. Measure and prose

```css
.prose {
  max-inline-size: var(--measure); /* 60–70ch lands in the 45–75 character range */
  font-family: var(--font-text);
  font-size: var(--text-base);
  line-height: 1.6;
  text-wrap: pretty;
}

.prose > * + * {
  margin-block-start: 0.75em; /* paragraph gap, less than a full line */
}

.prose h2,
.prose h3 {
  line-height: var(--leading-tight);
  text-wrap: balance;
  margin-block-start: 1.5em;
  margin-block-end: 0.5em;
}

.prose > :first-child { margin-block-start: 0; }
```

Do not centre the prose block with `margin-inline: auto` on a wide page; place it asymmetrically and let the outer margin be large. If you do centre it, vary the margins so the grid remains visible.

## 3. Fluid type

```css
/* Grow between 20rem and 80rem of viewport, never outside the caps. */
h1 {
  font-size: clamp(2.5rem, 1.6rem + 4.5vw, 5rem);
  line-height: 0.95;
  letter-spacing: -0.02em;
  text-wrap: balance;
}

.lead {
  font-size: clamp(1.125rem, 1rem + 0.6vw, 1.375rem);
  line-height: 1.45;
}
```

- `clamp(min, preferred, max)` — the preferred value should be a mix of `rem` and `vw`, not `vw` alone, so zoom and user font size still work.
- Never let a headline grow past the point where it stops being a headline.
- Keep body copy off `vw` units above 20 px; users zoom for a reason.

## 4. Page shell and the 12-column grid

```css
.page {
  inline-size: min(100% - 2 * var(--page-margin), var(--content-max));
  margin-inline: auto; /* a centred frame; keep the content inside asymmetric */
}

/* Or push the frame off-centre and let the margin do the talking. */
.page--offset {
  margin-inline: var(--page-margin) auto;
}

.grid {
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  column-gap: var(--gutter);
  row-gap: var(--leading);
  align-items: start; /* align top edges; do not stretch cards by default */
}

.grid > .span-4  { grid-column: span 4; }
.grid > .span-6  { grid-column: span 6; }
.grid > .span-8  { grid-column: span 8; }
.grid > .span-12 { grid-column: 1 / -1; }
```

`minmax(0, 1fr)` prevents long words from blowing out a track. `align-items: start` keeps cards from stretching to the tallest neighbour, which is what makes a modular grid look accidental.

## 5. Asymmetric editorial layout

```css
.editorial {
  display: grid;
  grid-template-columns: minmax(0, 2.2fr) minmax(14rem, 1fr);
  gap: calc(2 * var(--gutter)) var(--gutter);
  align-items: start;
}

.editorial__rail {
  position: sticky;
  inset-block-start: 6rem;
}

@media (max-width: 48rem) {
  .editorial { grid-template-columns: 1fr; }
  .editorial__rail { position: static; }
}
```

Unequal tracks plus flush-left content are what make the structure legible. Equal halves are a valid choice, but they are a choice.

## 6. Hierarchy of spacing

```css
/* Inside a group: tight. Between groups: loose. */
.card__eyebrow { margin-block-end: var(--space-2); }
.card__title   { margin-block-end: var(--space-3); }
.card__body    { margin-block-end: var(--space-4); }

.section + .section { margin-block-start: var(--space-16); }
```

The rule, in one line: **space inside a group < space between groups**. If a heading sits closer to the previous section than to its own text, the grouping is broken.

## 7. Cards without the template look

```css
.cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr));
  gap: var(--gutter);
}

.card {
  display: grid;
  grid-template-rows: auto 1fr auto;
  gap: var(--space-3);
  padding: var(--space-4);
}

/* One card may claim two columns and become the focal point. */
.card--feature { grid-column: span 2; }

@media (max-width: 40rem) {
  .card--feature { grid-column: auto; }
}
```

A grid of identical cards is a legitimate pattern, but it has no hierarchy. Make one card larger, or let one row span the full width, or vary the density deliberately.

## 8. Breaking out of the container

```css
.full-bleed {
  inline-size: 100vw;
  margin-inline: calc(50% - 50vw);
}

/* Safer where scrollbars are overlay or classic. */
.breakout {
  inline-size: min(100vw - 2rem, 90rem);
  margin-inline: calc((100% - min(100vw - 2rem, 90rem)) / 2);
}
```

`100vw` includes the scrollbar in some browsers and causes a horizontal scrollbar. Prefer the second form, or set `overflow-x: clip` on the page and accept the risk.

## 9. Overlap and layered composition

```css
.spread {
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  align-items: center;
}

.spread__image {
  grid-column: 1 / 8;
  grid-row: 1;
  aspect-ratio: 4 / 3;
  object-fit: cover;
}

.spread__note {
  grid-column: 6 / 13;
  grid-row: 1;
  z-index: 1;
  background: var(--surface);
  padding: var(--space-6);
}
```

Overlap creates depth and new relationships. It also creates contrast and tap-target problems: check the text over the image at every width, and keep one element strictly aligned so the composition has an anchor.

## 10. Responsive: mobile first, container-aware

```css
.related {
  container-type: inline-size;
}

.related__list {
  display: grid;
  gap: var(--gutter);
  grid-template-columns: 1fr;
}

@container (min-width: 38rem) {
  .related__list { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}

@container (min-width: 64rem) {
  .related__list { grid-template-columns: repeat(4, minmax(0, 1fr)); }
}
```

Container queries respond to the slot, so the same component can be a single column in a rail and a four-up row in the main area. Use media queries for the page shell and container queries for components.

## 11. Optical details

```css
/* Caps and labels */
.eyebrow {
  font-size: var(--text-xs);
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

/* Small caps, only if the font has them */
.abbr {
  font-variant-caps: all-small-caps;
  letter-spacing: 0.02em;
}

/* Numbers that must line up */
.data {
  font-variant-numeric: tabular-nums lining-nums;
}

/* Hanging opening punctuation, where supported */
.prose p {
  hanging-punctuation: first allow-end;
}

/* Fallback: apply only to blocks that actually begin with a quote. */
.starts-with-quote { text-indent: -0.35em; }

/* Optical alignment of a quote mark in a pull quote */
.pullquote::before {
  content: "“";
  float: inline-start;
  margin-inline-start: -0.42em;
}
```

Never letter-space lowercase. Never fake small caps with `font-size` on capitals.

## 12. Font loading without layout shift

```css
@font-face {
  font-family: "Text";
  src: url("/fonts/text-regular.woff2") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
  size-adjust: 100%; /* tune against the fallback */
}

@font-face {
  font-family: "Text Fallback";
  src: local("Georgia");
  size-adjust: 104%;
  ascent-override: 92%;
  descent-override: 24%;
  line-gap-override: 0%;
}

body {
  font-family: "Text", "Text Fallback", Georgia, serif;
}
```

- Subset to the languages you ship; do not load a 400 KB Latin font for one headline.
- `font-display: swap` shows the fallback immediately; `optional` avoids any shift but may never show the webfont.
- Match fallback metrics so the swap does not move the layout.

## 13. Dark mode

```css
:root {
  --paper: #f4f1e8;
  --ink: #191b17;
  --muted: #54574b;
  --line: #d1cec2;
  --surface: #ffffff;
  --accent: #ec52b9;
}

@media (prefers-color-scheme: dark) {
  :root {
    --paper: #14150f;
    --ink: #f2efe4;
    --muted: #b9b9aa;
    --line: #33352c;
    --surface: #1c1e17;
    --accent: #ff7ac8;
  }
}
```

- Do not simply invert; tune each token for the same contrast relationships.
- Dark mode needs slightly lighter type and often slightly more line height.
- Test images, shadows, and focus rings in both modes; a black shadow disappears on a dark surface.
- `color-scheme: light dark` gives native form controls and scrollbars the right appearance.

## 14. Accessible interactive defaults

```css
:where(a, button, input, select, textarea, summary):focus-visible {
  outline: 3px solid var(--ink);
  outline-offset: 3px;
  border-radius: 2px;
}

.skip-link {
  position: absolute;
  inset-block-start: 0.5rem;
  inset-inline-start: 0.5rem;
  z-index: 100;
  transform: translateY(-200%);
  background: var(--surface);
  padding: 0.75rem 1rem;
}
.skip-link:focus { transform: none; }
```

- Keep the focus ring on every interactive element, including custom components.
- Do not remove the outline and replace it with `box-shadow` that disappears in forced-colours mode.
- Use `:focus-visible`, not `:focus`, for pointer users; still keep `:focus` fallbacks for older browsers if needed.

## 15. Reduced motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

Animate to explain a change, not to decorate. Parallax, autoplaying carousels, and looping background video need a pause control or an off switch.

## 16. Right-to-left and logical properties

```css
.card {
  margin-inline-start: var(--space-4);
  padding-inline: var(--space-3);
  border-inline-start: 2px solid var(--line);
  text-align: start;
}
```

- Prefer `inline-start` / `inline-end` over `left` / `right`.
- Set `dir="rtl"` on `<html>` or the component; `text-align: start` follows automatically.
- Mirror directional icons with `transform: scaleX(-1)` only when the icon means direction, not when it depicts an object.
- For Arabic, raise line height; the script has more vertical activity than Latin. Choose a font with real Arabic, and align its middle line with the Latin baseline when the two are mixed.

## 17. Forced colours and print

```css
@media (forced-colors: active) {
  .card { border: 1px solid CanvasText; }
}

@media print {
  .site-header, .site-footer, .no-print { display: none; }
  .prose { max-inline-size: none; }
  a[href]::after { content: " (" attr(href) ")"; font-size: 0.8em; }
}
```

High-contrast mode removes background images and shadows; anything that relied on them needs a border or a text cue.
