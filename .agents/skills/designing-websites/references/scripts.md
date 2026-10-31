# Multiscript typography

Depth behind §9 of the skill. From the script essays in Lupton's *Thinking with Type*, 3rd edition (Arabic by Apelian and Morcos; Chinese by Lam and Park; Korean by Jang and Lee; Japanese by Nishizuka; Indic by Chandra; Kigelia by Jamra and Patel), with CSS notes.

## Principles

- A script is cultural heritage, not a decoration. Do not homogenise it into Latin habits to make a template fit.
- Direction, alignment, line height, word spacing, and emphasis all differ by script. A "neutral" default is usually a Latin default.
- Use a font that genuinely covers the script. Fallback fonts change the voice, the metrics, and often the shaping.
- Never synthesise bold, italic, or small caps for a script that does not have them. Never letter-space a connected script.
- Test with real sentences from native speakers, at real sizes, not with transliterations or lorem ipsum.

## Arabic

- **Right to left.** Natural alignment is flush right; books bind with the spine on the right. Set `dir="rtl"` and use logical properties.
- **No upper- or lowercase.** Letters change form by position: initial, medial, final, isolated. The base drawing (*rasm*) is shared; dots distinguish letters. The system looks organic but is predictable.
- **About 29 letters in the book's count: 26 consonants and 3 vowels.** Short vowels sit above or below consonants and are often omitted in everyday text. Consonant-based systems are *abjads*.
- **Elongation** (*tatweel* or *madd*, also *kashida*) stretches a letter to justify a line or add emphasis. The character itself becomes spacing.
- **Ligatures and fusions** affect word shaping, readability, word spacing, and paragraph texture.
- **Emphasis:** Latin italics have no direct equivalent. Use a different calligraphic style, a weight change, or a colour change.
- **Numerals:** 0–9 are Hindu-Arabic; Eastern Arabic numerals read left to right inside right-to-left text.
- **Mixing with Latin:** align the Arabic **middle line** with the Latin **baseline**. Arabic has horizontal stress, unlike Latin's vertical emphasis, so matching x-heights alone is not enough.
- **Families:** *naskh* is the usual text style; *thuluth*, *diwani*, and *nastaliq* are more calligraphic. Kufic-derived designs are geometric and solid. The script also writes Persian, Urdu, Pashto, and Punjabi, with additional letters.

```css
[lang="ar"] {
  direction: rtl;
  text-align: start;
  font-family: "Noto Naskh Arabic", "Geeza Pro", serif;
  line-height: 2; /* more vertical room than Latin */
  letter-spacing: 0;
}
```

## Chinese

- The unit is the **character**, not the alphabet. Most characters are phono-semantic: one component suggests meaning, another suggests sound.
- Of 80,000+ extant characters, fewer than 10,000 are in common use; a display face may carry only a few thousand.
- **Monospaced, with no word spaces.** Density runs from one stroke to more than thirty, which makes the typographic colour darker than Latin.
- Characters do not sit on a baseline; alignment uses their **internal axes and centres of gravity**. Never align Latin to the top or bottom edge of a character.
- A line of body text commonly holds **20–30 characters**, usually fully justified; shorter text may be flush left. Line spacing is greater than in Latin, and the same content runs about half as long.
- **Traditional and simplified** orthographies are distinct. Simplified was promulgated in 1956 and is used in mainland China, Singapore, and the UN; traditional forms remain in Hong Kong, Taiwan, and overseas communities. Both have variant forms.
- Four families: **Kaiti** (regular script, the calligraphic reference), **Songti / Mingti** (the first true printed Chinese face, rectilinear with triangular terminals, associated with books), **Imitation Song** (a twentieth-century revival, common in mainland documents), **Heiti** (a grotesque-derived sans, now widespread).

```css
[lang="zh"] {
  font-family: "Noto Serif SC", "Songti SC", serif;
  line-height: 1.8;
  text-align: justify;
  letter-spacing: 0;
  line-break: strict;
}
```

## Korean

- **Hangeul** was invented in 1443 by King Sejong and promulgated in 1446; it was printed before it was widely handwritten, which makes it "typographically native".
- The five basic consonants derive from vocal-organ shapes; nine more add strokes; five doubles repeat a letter. Modern Hangeul uses **24 basic letters** (14 consonants and 10 vowels in the standard count). Vowels derive from heaven (dot), earth (line), and human (vertical).
- Letters assemble into syllable blocks: initial consonant, medial vowel, final consonant. A complete Unicode font needs **19 initials × 21 medials × 28 finals = 11,172 syllables**; many fonts supply the 2,350 most common.
- **Square** faces resize components to fit the block; **de-squared** faces keep component forms and let the block grow taller, with the final consonant outside the square.
- Hangeul is compact: no ascenders or descenders, even colour, mostly monospaced. It reads shorter and darker than Latin at the same size.
- **Serif analogue:** Batang / Myeongjo. **Sans analogue:** Dotum / Gothic. Also Gungseo (script) and display faces.
- When pairing with Latin: set Hangeul slightly **smaller** with **more leading**, and shift the Latin baseline so its ascenders and descenders match the Hangeul top and bottom lines.

```css
[lang="ko"] {
  font-family: "Noto Serif KR", "Apple SD Gothic Neo", serif;
  line-height: 1.9;
  letter-spacing: 0;
  word-break: keep-all;
}
```

## Japanese

- **Kanji** (ideographic, from China) plus **hiragana** and **katakana** (syllabic). Hiragana simplified *manyogana* in the ninth century; katakana arose by omitting strokes to save space.
- Kanji occupy **90–95%** of the square body; kana occupy **83–88%**. The body is conventionally **1000 × 1000 units**.
- Kana are the majority of running text and must be drawn for readability, not treated as a garnish.
- Styles: **Mincho** (serif), **Gothic** (sans), **Rounded Gothic**. Japanese text normally includes Latin too.
- **Vertical-only glyphs** exist for punctuation and small kana; substitute them when `writing-mode` changes.
- In vertical setting the centre line is 500 units; horizontally the Latin baseline sits at 880 of 1000, with 120 below. Enlarging Latin to optically match kanji often makes it look too large.
- Vertical numbers usually use kanji numerals; two-digit-or-fewer numbers may be upright Hindu-Arabic. Latin is normally rotated 90°, but two- or three-character words may sit upright as **tate-chu-yoko** ("a horizontal line in a vertical line").
- At display sizes, kana can look loose; proportional metrics and kerning pairs tighten them.

```css
[lang="ja"] {
  font-family: "Noto Serif JP", "Hiragino Mincho ProN", serif;
  line-height: 1.9;
  letter-spacing: 0;
  line-break: strict;
}

.vertical {
  writing-mode: vertical-rl;
  text-orientation: mixed;
}
```

## Indic

- **Abugida:** each unit is a base consonant plus a secondary vowel. Consonants are modified by **matras** (diacritics); adding the i-matra to *ka* gives *ki*.
- **Conjuncts** combine consonants for correct phonetics (*ma* + *ta* + *sa* + *ya* = *tsya*). They change a word's shape and width unpredictably.
- India's 2001 census counted 122 major languages and 1,599 others. Devanagari supports 120+ languages; Bangla is the world's fifth most widely used script.
- North Indian scripts (Indo-European) were written with broad-nib pens and carry **45° stress**; South Indian scripts (Dravidian) were written with styluses, producing **monoline** letters without contrast, to which colonial founders later added contrast.
- **Devanagari, Bangla, and Gurmukhi share the shirorekha**, the horizontal headstroke from which letters hang, with full- and half-length vertical bars. Gujarati lacks the headstroke but keeps the other structural traits. Many scripts hang from a headline rather than sitting on a baseline.
- Styles are **traditional** (serif-like), **modern** (sans-like), and **display**.
- Matching Latin and Indic body texture is the hardest problem: Devanagari is more complex and is drawn lighter with more white space; Kannada and Telugu have horizontal rather than vertical contrast and multiple matra levels below the baseline.
- Large multiscript families should match scripts "without homogenizing them."

```css
[lang="hi"] {
  font-family: "Noto Sans Devanagari", "Kohinoor Devanagari", sans-serif;
  line-height: 1.8;
  letter-spacing: 0;
}
```

## African scripts

Kigelia (Mark Jamra and Neil Patel) supports N’ko, ADLaM, Vai, Ge’ez, Tifinagh, Osmanya, Arabic, Latin, Cyrillic, and Greek, and was designed **with mobile devices in mind** — phones, not desktops, drive much communication and commerce across Africa.

| Script | Type | Direction | Speakers | Note |
|---|---|---|---|---|
| **ADLaM** | Alphabet | RTL | ~50 million | Fulfulde/Pular; created in the 1980s in Guinea; connected and unconnected forms |
| **Ge'ez** | Abugida | LTR | ~65 million | Amharic, Tigrinya; over 2,000 years old; began as an abjad, gained vocalic diacritics |
| **N’ko** | Alphabet | RTL | ~40 million | Manding; invented 1949; marks vowels and tones because Manding is tonal |
| **Osmanya** | Alphabet | LTR | ~16.6 million | Somali; invented 1920–22; now mainly historical |
| **Tifinagh** | Abjad / alphabet | LTR or RTL | ~20 million | Amazigh/Tuareg; Neo-Tifinagh adds vowels and is taught in some Moroccan schools |
| **Vai** | Syllabary | LTR | ~119,500 | Created 1830; Kigelia includes about 300 Vai glyphs |

The barrier is not only glyphs but the **lack of content** in African languages. A typeface alone does not make a site multilingual; the copy has to exist.

## CSS checklist for any non-Latin locale

- [ ] `dir` and `lang` are set on the document and on inline passages.
- [ ] Logical properties (`margin-inline`, `padding-inline`, `inset-inline`, `border-inline-start`) are used.
- [ ] Font stack is script-specific, with a real fallback, not a Latin face.
- [ ] `letter-spacing: 0` for connected and monospaced scripts.
- [ ] No `text-transform`; case may not exist.
- [ ] Line height is increased where the script has more vertical activity (Arabic, Devanagari, CJK).
- [ ] `word-break: keep-all` for Korean; `line-break: strict` for CJK.
- [ ] Vertical writing, if offered, uses `writing-mode` and `text-orientation`, and has vertical-only glyphs.
- [ ] Numerals and dates follow the locale, not the developer's.
- [ ] Content is reviewed by a native reader, in context, on a phone.
