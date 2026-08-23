# /// script
# requires-python = ">=3.11"
# dependencies = ["pymupdf"]
# ///
"""Draft a toc.txt for pdf.tocgen's `pdftocio`.

The PDF outline is NOT free: it exists only because a toc.txt was written by
hand and piped into pdftocio. This drafts one so that is editing rather than
typing -- it is a starting point, not an answer. You must check it.

Chapter openers are found by geometry: a large line, near the left margin, high
on an otherwise sparse page. Titles are OCR'd through a decorative icon, so they
come out mangled ("8 The Behavioral Interview"). The book's own printed contents
page is dumped too -- copy the correct wording from there.

  propose_toc.py out_ocr_out.pdf [--book book.json] > toc.txt
  # edit, then:  pdftocio out_ocr.pdf < toc.txt
"""

import argparse
import json
import re
import sys
from pathlib import Path

import fitz

ap = argparse.ArgumentParser()
ap.add_argument("pdf")
ap.add_argument("--book", help="book.json, for the measured geometry")
ap.add_argument("--band", default="20:170", help="y range of the title zone")
args = ap.parse_args()

doc = fitz.open(args.pdf)
col_x0, heading_min = 64.0, 9.5
if args.book:
    g = json.loads(Path(args.book).read_text())["geometry"]
    col_x0, heading_min = float(g["col_x0"]), float(g["heading_min"])
y_lo, y_hi = (float(v) for v in args.band.split(":"))
BIG = heading_min * 1.35


def lines_of(page):
    out = []
    for b in page.get_text("dict")["blocks"]:
        if b["type"] != 0:
            continue
        for ln in b["lines"]:
            t = "".join(s["text"] for s in ln["spans"]).strip()
            if not t:
                continue
            dom = max(ln["spans"], key=lambda s: len(s["text"]))["size"]
            x0, y0, x1, y1 = ln["bbox"]
            out.append({"t": t, "x0": x0, "y0": y0, "y1": y1, "d": dom})
    return sorted(out, key=lambda ln: ln["y0"])


def strip_icon(t):
    """Drop the OCR'd decorative glyph in front of a chapter title."""
    t = re.sub(r'^[^\w"“(]+\s*', "", t)
    m = re.match(r"^(\S{1,3})\s+(?=[A-Z])", t)  # stray "8 ", "GY ", "all "
    if m and m.group(1).lower() not in {"the", "a", "an"}:  # not a real title word
        t = t[m.end():]
    return t.strip()


hits = []
for pno, page in enumerate(doc, 1):
    lines = lines_of(page)
    if not lines:
        continue

    # Part dividers: a nearly empty page whose text is just "PART II / THE
    # COMPETENCIES". They sit lower than the title band, so catch them first.
    flat = " ".join(ln["t"] for ln in lines)
    if len(flat) < 60 and re.match(r"^\s*part\b", flat, re.I):
        hits.append((pno, " ".join(flat.split()).replace(" :", ":")))
        continue

    big = [
        ln for ln in lines
        if ln["d"] >= BIG and y_lo <= ln["y0"] <= y_hi and ln["x0"] < col_x0 + 35
    ]
    if not big:
        continue
    head = big[0]
    # A chapter opener is sparse up top: body copy starts well below the title.
    body_below = [ln for ln in lines if ln["y0"] > head["y1"] + 4 and ln["d"] < BIG]
    if body_below and body_below[0]["y0"] - head["y1"] < 25:
        continue  # text resumes immediately -- a figure label, not a title

    title = strip_icon(head["t"])
    for ln in big[1:]:  # wrapped second line of the title
        if 0 < ln["y0"] - head["y1"] < 22:
            title += " " + strip_icon(ln["t"])
    if len(re.sub(r"[^A-Za-z]", "", title)) < 4:
        continue
    hits.append((pno, title))

print("# DRAFT -- check every line. Titles are OCR'd and may be mangled;", file=sys.stderr)
print("# copy the real wording from the printed contents dumped below.", file=sys.stderr)
for pno, title in hits:
    print(f'"{title}" {pno}')

# The book's own contents page, for correct titles.
for pno, page in enumerate(doc, 1):
    txt = page.get_text().strip()
    if re.match(r"^\s*contents\b", txt, re.I):
        print(f"\n--- printed contents, p{pno} (copy titles from here) ---", file=sys.stderr)
        print(txt[:1800], file=sys.stderr)
        break
