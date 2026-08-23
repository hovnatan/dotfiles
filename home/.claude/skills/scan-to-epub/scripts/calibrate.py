# /// script
# requires-python = ">=3.11"
# dependencies = ["pymupdf", "numpy"]
# ///
"""Measure a scanned book's layout and emit book.json.

Every number the builder needs is a property of *this* book. Guessing them is
how you silently delete text, so measure them and print the evidence.
"""

import argparse
import json
import re
from collections import Counter
from pathlib import Path

import fitz
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("pdf")
ap.add_argument("-o", "--out", default="book.json")
args = ap.parse_args()

doc = fitz.open(args.pdf)
W, H = doc[0].rect.width, doc[0].rect.height
print(f"pages: {len(doc)}   page size: {W:.1f} x {H:.1f} pt\n")


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
            out.append({"t": t, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "d": dom})
    return out


pages = [lines_of(p) for p in doc]
alllines = [ln for p in pages for ln in p]

# ---- text column: the left edge nearly every line shares -------------------
x0s = Counter(round(ln["x0"]) for ln in alllines)
col_x0 = float(min(x for x, c in x0s.most_common(3)))
wide = [ln for ln in alllines if ln["x1"] - ln["x0"] > 0.4 * W]
col_x1 = float(np.percentile([ln["x1"] for ln in wide], 95)) if wide else W - col_x0
colw = col_x1 - col_x0
print(f"text column : x {col_x0:.1f} .. {col_x1:.1f}  (width {colw:.1f})")


def is_prose(ln):
    return (ln["x1"] - ln["x0"]) > 0.55 * colw and col_x0 - 6 <= ln["x0"] <= col_x0 + 26


prose = [ln for ln in alllines if is_prose(ln)]
body = float(np.median([ln["d"] for ln in prose]))
body_hi = float(np.percentile([ln["d"] for ln in prose], 99))
print(f"body type   : median {body:.2f}pt   p99 {body_hi:.2f}pt")

# ---- footer boundary -------------------------------------------------------
# The lowest real body line vs. the highest running foot. If these two overlap,
# no positional cutoff is safe and the layout needs a closer look.
body_max = max((ln["y0"] for ln in prose), default=0.0)
low = [ln for ln in alllines if ln["y0"] > body_max]
foot_min = min((ln["y0"] for ln in low), default=H)

print(f"\nlowest body line   y0 = {body_max:.1f}   {next((ln['t'][:44] for ln in prose if ln['y0'] == body_max), '')!r}")
print(f"highest footer     y0 = {foot_min:.1f}   {next((ln['t'][:44] for ln in low if ln['y0'] == foot_min), '')!r}")

if foot_min <= body_max:
    print("  !! body and footers overlap -- inspect manually before trusting footer_y")
    footer_y = round(body_max + 1, 1)
else:
    footer_y = round((body_max + foot_min) / 2, 1)
print(f"  => footer_y = {footer_y}  (drop everything at or below this)")

# ---- heading size ----------------------------------------------------------
# Two populations: prose, and short unpunctuated lines preceded by a gap (i.e.
# headings). Put the threshold in the gap *between* them. Do not use a
# percentile of prose alone -- bold run-in lines fit wider, so OCR gives them a
# larger size and they drag prose's p99 up into heading territory.
cand = []
for p in pages:
    ordered = sorted(p, key=lambda ln: ln["y0"])
    for i, ln in enumerate(ordered):
        if ln["y0"] >= footer_y:
            continue
        gap = ln["y0"] - ordered[i - 1]["y1"] if i else 99.0
        if (
            (ln["x1"] - ln["x0"]) < 0.85 * colw
            and ln["x0"] < col_x0 + 40
            and gap > 7.5
            and not ln["t"].rstrip().endswith((".", ",", ";", ":"))
        ):
            cand.append(ln["d"])

prose_hi = float(np.percentile([ln["d"] for ln in prose], 95))
if cand:
    head_lo = float(np.percentile(cand, 25))
    heading_min = round((prose_hi + head_lo) / 2, 2)
else:
    head_lo = float("nan")
    heading_min = round(prose_hi * 1.05, 2)

print(f"\nprose p95        = {prose_hi:.2f}pt")
print(f"heading-ish p25  = {head_lo:.2f}pt")
print(f"  => heading_min = {heading_min:.2f}pt")
if cand and head_lo <= prose_hi:
    print("  !! the two populations overlap -- headings may be missed; check by hand")

# ---- outline ---------------------------------------------------------------
toc = doc.get_toc()
print(f"\noutline entries: {len(toc)}")
for lvl, title, pg in toc:
    print(f"   L{lvl} p{pg:<4} {title}")
if not toc:
    print("   NONE. The outline is not automatic -- it comes from a hand-written")
    print("   toc.txt piped into pdftocio. Draft one with:")
    print("     propose_toc.py <pdf> --book book.json > toc.txt   # then EDIT it")
    print("     pdftocio out_ocr.pdf < toc.txt")
    print("   (or list sections in front_matter in book.json instead)")

# ---- pages worth skipping --------------------------------------------------
# Only auto-skip what is certainly not book text. Sparse pages are NOT safe to
# drop -- part dividers and epigraphs are nearly empty but are real content.
skip, review = [], []
for i, p in enumerate(pages, 1):
    txt = " ".join(ln["t"] for ln in p)
    if i in (1, len(doc)):
        skip.append((i, "cover / back cover"))
    elif re.match(r"^\s*contents\b", txt, re.I):
        skip.append((i, "printed TOC (EPUB has its own nav)"))
    elif len(txt) < 40:
        review.append((i, f"sparse: {txt[:36]!r}"))

print("\nskip_pages (auto):")
for i, why in skip:
    print(f"   p{i}: {why}")
print("review by hand -- sparse, but often REAL content (part dividers, epigraphs):")
for i, why in review:
    print(f"   p{i}: {why}")

# single-page outline sections are usually part dividers: big type, real text
part_pages = []
for k, (lvl, title, pg) in enumerate(toc):
    nxt = toc[k + 1][2] if k + 1 < len(toc) else len(doc) + 1
    if nxt - pg == 1 and re.match(r"^\s*part\b", title, re.I):
        part_pages.append(pg)

cfg = {
    "pdf": str(Path(args.pdf).resolve()),
    "cover": "",
    "title": "",
    "author": "",
    "publisher": "",
    "language": "en",
    "geometry": {
        "col_x0": round(col_x0, 1),
        "col_x1": round(col_x1, 1),
        "footer_y": footer_y,
        "heading_min": heading_min,
    },
    "skip_pages": [i for i, _ in skip],
    "text_only_pages": part_pages,
    "no_fig_pages": [],
    "front_matter": [],
    "known_headings": [],
    "ocr_fixes": [["\\bAl\\b", "AI"]],
}
Path(args.out).write_text(json.dumps(cfg, indent=2) + "\n")
print(f"\nwrote {args.out} -- fill in title/author/cover, then review skip_pages")
