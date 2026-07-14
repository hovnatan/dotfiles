---
name: scan-to-epub
description: Convert an OCR'd scanned book PDF (OCRmyPDF output) into a reflowable EPUB for Kindle/e-readers, recovering headings, lists, figures, and bold/italic. Use when the user wants an EPUB or e-reader version of a scanned book, or to convert a scan/PDF for their Kindle.
---

# Scanned PDF -> reflowable EPUB

Turns an OCR'd book scan into a proper reflowable EPUB: real chapters and TOC,
headings, lists, diagrams as images, and bold/italic.

Input is an OCRmyPDF-produced PDF: pages are raster images with an invisible OCR
text layer.

## The pipeline

```
raw scans -> ScanTailor Advanced -> convert_to_pdf.sh -> [this skill] -> .epub
```

## Before any of this: ScanTailor

The pipeline starts from **ScanTailor** output, not from raw photos or a phone
scan. Run it first: it splits spreads into pages, deskews, de-margins, and
binarizes to clean bitonal TIFFs. Then `convert_to_pdf.sh` turns those into the
OCR'd PDF this skill consumes.

This is not optional polish. Every heuristic here reads the page **geometry** —
a heading is "larger type, near the left margin, high on the page"; a footer is
"below y=620". On skewed, un-cropped pages those statements are meaningless and
the whole approach collapses. ScanTailor is what makes the coordinates mean
something.

On macOS ScanTailor is **not in Homebrew**. It comes from **MacPorts**:

```bash
sudo port install scantailor        # /opt/local/bin/port
```

The port is plain `scantailor` (currently 0.2.9) — despite the name it is the
scantailor.org fork that merges the Featured and Enhanced features, which is the
"Advanced"-class build you want. There is no separate `scantailor-advanced` port.

Note MacPorts lives in `/opt/local/bin`, which is often absent from a
non-interactive shell's PATH — use the full path if `port` is "not found".

The rest of the toolchain is Homebrew:

```bash
brew install imagemagick poppler ocrmypdf mediainfo jbig2
```

Keep the ScanTailor project file. If a page comes out wrong later, it is usually
faster to fix the segmentation there and re-run than to special-case it in code.

## Making the PDF: `convert_to_pdf.sh`

`~/.dotfiles/scripts/pdf_tools/convert_to_pdf.sh` turns the ScanTailor TIFFs into
the OCR'd PDF this skill reads.

```bash
convert_to_pdf.sh <scantailor-output-folder>     # folder holding the *.tif
```

It writes everything into `<folder>/out_pdf/`:

| file | what it is |
|---|---|
| `1_XXX.pdf` | one PDF per page (JPEG for colour pages, bitonal otherwise) |
| `out.pdf` | all pages merged (`pdfunite`) |
| `out_ocr.pdf` | + OCR text layer (`ocrmypdf`) |
| `out_ocr.txt` | plain-text sidecar, handy for grepping |
| **`out_ocr_out.pdf`** | + the TOC outline (`pdftocio`) — **this is the skill's input** |

Note the `_out` suffix: `pdftocio` appends it. Feed that file to `calibrate.py`,
not `out_ocr.pdf`.

**Chicken-and-egg on the first run.** The last line of the script pipes
`<folder>/toc.txt` into `pdftocio`, but you cannot write `toc.txt` until you have
a PDF to read page numbers from. So the first run **fails on that last line** —
which is fine, `out_ocr.pdf` already exists by then. Do:

```bash
convert_to_pdf.sh <folder>                                  # fails at pdftocio: no toc.txt
propose_toc.py <folder>/out_pdf/out_ocr.pdf > toc.txt       # draft it, then EDIT
mv toc.txt <folder>/toc.txt
pdftocio <folder>/out_pdf/out_ocr.pdf < <folder>/toc.txt    # -> out_ocr_out.pdf
```

(Or just re-run `convert_to_pdf.sh` once `toc.txt` exists — it redoes the OCR,
which is slower but simpler.)

## The one rule

**Measure, never assume.** Every constant here (footer boundary, text column,
heading size) is a property of *this book's* layout. Guessing them is how you
silently delete text. A previous run hardcoded a footer cutoff one point too
high and deleted 67 lines of body copy — and the verifier reused the same
constant, so it reported "zero loss" and looked fine. Calibrate, then verify
with checks that do not share assumptions with the code they check.

## Workflow

### 0. The TOC is manual. Budget for it.

The builder takes its sections from the PDF's outline. That outline is **not
free** — it is there only because a `toc.txt` was written **by hand** and piped
into `pdftocio` (the last line of `convert_to_pdf.sh`). Expect to do this for
every new book. There is no chapter list hiding in a scan.

To make it editing rather than typing:

```bash
uv run scripts/propose_toc.py out_ocr_out.pdf --book book.json > toc.txt
```

It finds chapter openers by geometry and dumps the book's printed contents page
to stderr so you can copy the real wording. **It is a draft.** It will include
junk (cover, title page, the odd figure caption) and the titles are OCR'd
through decorative icons, so they come out mangled. Delete the junk, fix the
wording, keep the page numbers — those are the part it gets reliably right.

Then re-stamp the outline and rebuild `book.json` from the new PDF:

```bash
pdftocio out_ocr.pdf < toc.txt        # -> out_ocr_out.pdf, now with an outline
```

If a PDF genuinely has no outline, the builder will refuse rather than silently
produce a one-chapter blob. Add sections to `front_matter` in `book.json`
instead.

### 1. Calibrate

```bash
uv run scripts/calibrate.py path/to/out_ocr_out.pdf -o book.json
```

Prints the measured geometry and writes `book.json`. **Read the report.** It
tells you the lowest body line vs. the highest running foot — if those overlap,
the layout is unusual and the heuristics need a second look. Fill in title /
author / cover.

Front matter before the first outline entry (copyright, dedication) is not in
the outline; add it to `front_matter` if you want it.

### 2. Build

```bash
uv run scripts/build_epub.py book.json -o out.epub
```

### 3. Verify — do not skip, and do not trust a clean result you did not test

```bash
uv run scripts/verify_coverage.py book.json out.epub   # nothing was DROPPED
uv run scripts/lint_epub.py out.epub                   # what survived is not CORRUPT
uvx --from epubcheck epubcheck out.epub                # valid EPUB
```

Two different failure modes, two different checks. Coverage cannot see mangled
text (all the words are still present); the lint cannot see deleted text (it
only reads what is there). You need both.

Then **look at the figures** — dump `OEBPS/images/fig*.png` into a contact sheet
and eyeball them. Phantom figures and swallowed headings are invisible to both
checks, because both deliberately ignore anything inside a figure box.

Expected: coverage `MISSING: 0`; lint `paragraphs starting lowercase: 0`;
epubcheck silent.

## Reading the lint

`paragraphs starting lowercase` is the highest-value signal in the whole
pipeline. It is the fingerprint of dropped or mis-joined text. Anything above 0
is a real defect — chase every one. Typical causes:

- a bullet's continuation on the next page failed to rejoin its item
- a hyphenated word split across a page break
- a figure box swallowed a line of prose

The other lint counts are advisory and have benign explanations (run-in labels
legitimately lack terminal punctuation; unknown words are mostly tech jargon).

## How it works (and what will surprise you)

**Structure from geometry.** OCRmyPDF scales its invisible text to match the
scanned type, so font size and position still carry structure. Headings are
larger + short + preceded by a gap; lists are marker + indent; paragraphs are
vertical spacing. See `references/method.md`.

**Figures from residual ink.** Mask OCR word boxes off the page ink; whatever
remains is graphics. Crop it out at 300 DPI and embed. Bitonal line art is
exactly right for e-ink — do not chase colour originals for a B&W interior.

**Bold/italic from pixels, not from OCR.** This surprises people:

- OCRmyPDF's text layer uses a *single glyphless font*. It structurally cannot
  carry styling. No flag fixes this.
- Tesseract's LSTM engine reports no styling at all.
- Tesseract's *legacy* engine (`--oem 0`) claims to, and is the usual advice
  online. It is **useless** — tested on a real book, it tagged stray `I`, `-`,
  `.` as bold and missed every actual bold heading.

So measure the glyphs: **bold = thicker strokes** (distance transform), **italic
= slanted stems** (best shear angle). Thresholds are relative to each page's own
median, so scan-darkness drift does not matter. This works very well — bold was
essentially perfect, italic caught genuine mid-sentence emphasis.

## Traps this code already handles

Do not "simplify" these away; each one was a real bug found by verification:

- **Measure ink on the raw mask, never the dilated one.** A single stray speck
  dilates to ~81px and fabricates phantom figures out of nothing.
- **Thin long strokes are printed rules**, not artwork. Left in, a rule seeds a
  figure that swallows the heading it was underlining.
- **Judge a figure's size *after* it absorbs its captions**, not before — a
  diagram's seed can be just its icon row.
- **Tesseract reads diagram icons as huge "text"** (`ny`, `Da`, `£2` at 25-30pt),
  which masks their ink out of the graphics layer. Keep that ink — but only for
  gibberish, never for real words: some real headings are also set large.
- **An icon glyph inflates its line's max font size** ("F Red Flags" -> 13.4pt).
  Use the size of the span with the most characters, not the max.
- **Full-width lines in the text column are prose and can never be part of a
  figure**, whatever the geometry says. This is the guard that makes text loss
  structurally impossible.
- **A caption never ends in a period** — that is how you tell a diagram label
  from a paragraph's last line sitting above the figure.

## Per-book work you cannot avoid

`book.json` needs human eyes: cover page, back cover, printed-TOC page (drop it,
the EPUB has its own nav), and any colophon/barcode page. `known_headings` is
optional — it strips OCR'd icon junk off recurring headings (`oll Key Signals`,
`F Red Flags`), so list the book's recurring section headings if it has them.
