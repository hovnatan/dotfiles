# Method

Why each stage works, and what it costs you to get it wrong.

## Stage 0: ScanTailor (before anything here)

Raw scans -> **ScanTailor Advanced** -> `convert_to_pdf.sh` -> the OCR'd PDF this
skill reads. macOS: MacPorts, not Homebrew (`port search scantailor`).

Everything downstream assumes page coordinates *mean* something: that x=64 is
the left margin on every page, that y>=620 is the footer band, that a line 2pt
taller than its neighbours is a heading. A 1-degree skew or a few millimetres of
crop drift breaks all of it — the footer cutoff starts slicing body text on some
pages and missing footers on others.

ScanTailor is what earns those assumptions: deskew, de-margin, consistent page
box, clean binarization. Do not try to compensate for a bad scan in the
heuristics; fix it in ScanTailor and re-run.

## What the input actually is

OCRmyPDF output: each page is a raster image (bitonal JBIG2 after ScanTailor)
with an **invisible text layer** drawn over it in a single glyphless font.

Two consequences that drive everything else:

- The text layer has **no styling** and **no structure** — no bold, no italic,
  no headings, no lists. Just words with boxes.
- But OCRmyPDF *scales each line's font size to match the scanned type*. So
  size and position still encode the structure. That is the whole opening.

## 1. Structure from geometry

| element | signal |
|---|---|
| heading | size >= `heading_min`, short line, gap above, no terminal punctuation, near left margin |
| list item | bullet/number glyph + indent past the text column |
| list wrap | no marker, gap < 8pt, indented >= the item's own `x0` |
| paragraph | consecutive lines, gap < 8pt |
| paragraph break | gap > ~18pt |
| footer | `y0 >= footer_y` |

**Sizes are noisy.** OCRmyPDF fits size per line, so a body line with descenders
can reach 9.4pt while a heading sits at 9.8pt. And an OCR'd icon glyph inflates
its line's *max* span size ("F Red Flags" -> 13.4pt). Use the size of the span
with the **most characters** (`dsize`), not the max.

**Wraps vary.** Some lists hang the wrap under the text (x0~85); others set it
flush with the bullet (x0~75). Test against *the item's own* indent, never a
fixed column.

**Paragraphs and bullets split across pages.** The continuation arrives with no
bullet of its own, so it must be able to merge back into a `li` as well as a
`p` — and the split may fall mid-word on a hyphen.

## 2. Dehyphenation without wrecking real compounds

A line-end hyphen is usually OCR's, but sometimes it's the author's
("trade-offs"). Build a vocabulary of hyphenated compounds that appear
*within* a line elsewhere in the book, then at a line break keep the hyphen only
if the joined form is in that vocabulary. Cheap and accurate.

Watch for OCR emitting a stray quote as its own line, landing between `obvi-`
and `ous.` and wrecking the join. Defer punctuation-only fragments past the
join.

## 3. Figures from residual ink

Mask the OCR word boxes off the page ink. **Whatever ink is left is graphics.**
Dilate to group strokes into blobs, merge blobs into diagrams, absorb the
diagram's labels, then crop at 300 DPI.

Hard-won details:

- **Measure ink on the raw mask, never the dilated one.** Dilation inflates a
  single speck to ~81px; thresholds tuned against that fabricate figures out of
  nothing.
- **Keep tiny blobs through the merge.** Connector arrows are what bridge a
  diagram's parts; drop them and "Key Signals" detaches from its items.
- **Drop long thin strokes** (raw height <= 5px, width >= 60px). Those are
  printed rules. A rule left in seeds a figure that swallows the heading it was
  underlining.
- **Judge size *after* absorbing captions.** A diagram's seed may be only its
  icon row; it reaches full size once the captions below join it.
- **Tesseract reads icons as huge "text"** (`ny`, `Da`, `£2` at 25-30pt), which
  masks their ink out of the graphics layer. Keep that ink — but only for
  gibberish (no 3+ letter word), never for real words: some real headings are
  set large too.
- **A caption never ends in a period.** That distinguishes a diagram label from
  a paragraph's last line sitting just above the figure.
- **Prose is sacred:** a full-width line in the text column can never be part of
  a figure, whatever the geometry says. This guard is what makes text loss
  structurally impossible rather than merely unlikely.

Bitonal line art at 300 DPI is ideal for e-ink. Do not chase colour originals
for a black-and-white interior; do use them for the cover.

## 4. Bold and italic from pixels

Not from OCR. See SKILL.md — the text layer cannot carry it, LSTM reports
nothing, and the legacy engine's output is noise.

- **bold** = stroke thickness: `2 * mean(distance_transform(ink))` per word.
- **italic** = slant: the shear `s` maximizing the sharpness of the column
  histogram after `x' = x + s*(y - y_centre)`. Italic leans right, so its stems
  align under a **positive** shear. (Get this sign backwards and you find
  nothing.)

Threshold against **each page's own median** (bold > 1.18x, italic > +0.08), so
scan-darkness drift between pages doesn't matter. Words under 3 characters are
too small to measure — let them inherit from their neighbours, or an italic
phrase fragments around every "to" and "of".

## 5. Verification

Two failure modes, two checks that must not share assumptions:

- **Coverage** — nothing dropped. Every non-footer, non-figure OCR line appears
  in the output. Cannot see corruption.
- **Lint** — nothing corrupted. `paragraphs starting lowercase` is the money
  signal. Cannot see deletion.
- **Your eyes** — the figures. Both checks ignore figure interiors by design.

The trap: a checker that reuses the code's own constants confirms the code's
assumptions instead of testing them. An earlier version of the coverage check
reused the buggy footer cutoff and cheerfully reported "zero loss" while 67
lines of body copy were being deleted. Derive the check's inputs from the
config and from what the builder actually emitted, not from a copy of its logic.
