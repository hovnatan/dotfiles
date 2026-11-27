---
name: book-scan
description: "Scanned book cleanup with ScanTailor Advanced: page images out of a PDF, the content boxes revised by a model, then the finished pages made into a searchable PDF with bookmarks. Load when I ask to clean, crop or prepare a scanned book, make a PDF of ScanTailor's output, or name ScanTailor."
---

# Book scan: page images, my ScanTailor steps, the content boxes, the PDF

Five steps, in order. I drive ScanTailor's window; you do the files before
and after it. Each book's images, project and run folders stay together in
one folder of the book's own.

## 1. Page images out of the PDF

Take each page's image as the PDF stores it: `pdfimages -list` to see what
is there, then `pdfimages -p -png -j <pdf> <folder>/img`. Rendering the
pages (`pdftoppm`, `magick`) resamples a scan that is already final.

- **One image a page.** An Acrobat scan carries one-pixel stencil images
  beside each page's real one: keep the real one, named `page-NNN.<ext>` by
  PDF page, so name order is reading order.
- **True dpi in the header.** `pdfimages` tags its PNGs 72 dpi and leaves
  JPEGs untagged. Write the resolution `-list` reports into each file's
  header (PNG `pHYs`, JPEG JFIF density) as a header edit, the pixels left
  as they are: ScanTailor's millimetres and step 3's all come from it.

Done when the folder holds one file per PDF page with none missing, every
file decodes, each header's dpi is `-list`'s, and a README there says how
it was made.

## 2. My steps in ScanTailor: geometry only

ScanTailor Advanced does geometry here and nothing else: each page upright,
single, straight and boxed. Nothing is binarised, despeckled, smoothed,
dewarped or given margins, so the images that come out in step 4 are the
scan's own pixels, deskewed and blank outside the content box, every page
one size with its content where it stood on the scanned page.

ScanTailor writes no image until its last step, Output, is run. Its last
two steps, Margins and Output, would by default add margins of 10 and 5 mm,
centre the content, and write black and white at 600 dpi, despeckled and
smoothed. Step 3's script sets both to geometry only in the project it
writes (its header lists the settings), so they are nobody's to click.

Ask me to open the page images in ScanTailor Advanced (`scantailor`, started
from a terminal), run the first four steps on every page (the arrow beside
a step's name runs it on all), and save the project beside the images:

1. **Fix Orientation**: nothing turned. A sideways scan is turned in the
   files, before the project is made.
2. **Split Pages**: one page an image. A two-page spread is split into two
   image files, before the project is made.
3. **Deskew**: automatic, a page left visibly crooked set by hand.
4. **Select Content**: automatic, the boxes left as they come: step 3
   revises them.

Done when I give you the saved project's path. Wait for it.

## 3. Content boxes

`scantailor_boxes.py <project>`, beside this file, rebuilds each page's box
from its ink, a model saying which regions are junk. Its header is the
reference: the run folder, resuming, overrides, what it refuses.

1. **Cost first.** Before the first paid call, tell me what the run will
   cost: pages times the price a page in the script's header.
2. **Pilot.** `--pages` with ten pages spread over the book: the first and
   last, a chapter opening, a figure, a page with handwriting if there is
   one. Open each pilot preview beside its verdict. Done when every verdict
   matches what the preview shows; a wrong one is a finding to bring me
   before the whole run.
3. **Whole run.** `--run-dir <the pilot's folder>`, in the background; its
   `events.log` is the progress.
4. **Review by eye, every sheet.** `compare/`: all printed content inside
   each green box. `junk/`: only shadows, lines, specks and handwriting
   among the crops. A miss goes in `overrides.jsonl`, the run is repeated
   with `--run-dir` (no call is paid for twice), and that page's sheet is
   looked at again. Done when every sheet of both folders has been looked
   at since the last change and shows no miss.

## 4. Hand over

- The revised project's path, and that the project I saved is untouched.
- What is mine to do with it in ScanTailor: page through Select Content and
  set right by hand any box that is wrong; see on one page that Margins
  reads 0 on all four sides with "Match size with other pages" on and both
  modes Original, and Output reads Color / Grayscale at the scan's dpi; then
  run Margins on every page, and after it Output on every page. Margins
  first, because the one size every page gets is settled only once all
  have passed it. The images land in the project's output folder (`out`
  beside the page images unless I chose another).
- That a black-and-white scan comes out as 8-bit grey: Color / Grayscale is
  the one Output mode that leaves the pixels alone.
- That thicker, smoother text is mine to choose at Output, at the price of
  pixels no longer the scan's: Mode set to Black and White, then the Otsu
  Threshold slider tried towards Thicker on one page until the text reads
  well. The setting holds for that page alone until Mode's "Apply To ..."
  is given All pages, and Output is then run on every page again.
- The pages the run's last lines list as still mixed or unsure: there
  handwriting or specks touch print and stay inside the box, for me to
  erase with fill zones at Output.
- A README in the run folder: pages kept, revised and taken whole again,
  the cost, what you looked at and what you did not, the commands.

Step 5 starts when I say Output has run.

## 5. The PDF

The book ends up in `pdf/` in its own folder, beside ScanTailor's output
folder. The bookmarks are a second pass: the book's own contents, mapped
to PDF pages through the text the first pass reads.

| File in `pdf/` | What it is |
| --- | --- |
| `ocr.pdf` | every page, searchable |
| `ocr.txt` | its text, a form feed between pages |
| `toc_printed.txt` | the contents by printed page number, typed by you |
| `toc.txt` | the same by PDF page |
| `book.pdf` | `ocr.pdf` with the bookmarks: the finished book |

1. **Output at rest.** ScanTailor can still be writing when I say it is
   done. Done when no file in the output folder has changed for 20 seconds
   and it holds one TIFF for each page of the project.
2. **Convert.** `convert_to_pdf.sh <output folder> <book folder>/pdf`,
   beside this file, what it prints kept as `convert.log` in a run folder.
   Where `ocrmypdf` is not installed, the script's header gives a
   `nix shell` line to run it inside. Done when the script exits 0 and
   `pdfinfo` counts a page of `ocr.pdf` for each TIFF. A book that prints
   no contents ends here, `ocr.pdf` the finished book.
3. **Contents typed.** Ask me which scan pages hold the contents unless I
   said. Read those page images and type `toc_printed.txt`: every entry of
   every level the book prints, with its printed page number, in the format
   `toc_pages.py`'s header gives.
4. **Pages mapped.** `toc_pages.py ocr.txt toc_printed.txt toc.txt`, beside
   this file. An entry it cannot place (preface, contents, a part's title
   page) you find in the OCR text and give its PDF page in `toc_printed.txt`
   as `=N`; a part that opens on an unnumbered title page points at that
   page. Render and look at the page behind every `LOOK` line and every
   `=N`. Done when nothing is unplaced and each of those pages has been
   seen to carry its heading.
5. **Bookmarks.** `uvx --from=pdf.tocgen pdftocio -t toc.txt -o book.pdf
   ocr.pdf`. Done when `pdftocio -p book.pdf` prints `toc.txt` back, under
   one line of deprecation warning, and `pdftotext` of a body page reads as
   that page.

Hand over the finished PDF's path, its pages and size, the pages tesseract
warned about in `convert.log`, which `LOOK` pages you saw and what the OCR
text was not checked for, and a section in the book's README with the
commands and the table of PDF page against printed number.
