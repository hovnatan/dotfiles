# /// script
# requires-python = ">=3.11"
# dependencies = ["pymupdf", "lxml"]
# ///
"""Nothing was DROPPED.

Invariant: every OCR line that is not a footer and not inside a figure must
appear in the EPUB.

This check must not share constants with the builder by hand-copying them --
that is exactly how an earlier version reported "zero loss" while the builder
was deleting 67 lines: both used the same wrong footer cutoff. It reads the
same book.json the builder used, and the figure boxes the builder actually
rasterized (the .figs.json sidecar it writes).
"""

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

import fitz
from lxml import etree

ap = argparse.ArgumentParser()
ap.add_argument("config")
ap.add_argument("epub")
args = ap.parse_args()

CFG = json.loads(Path(args.config).read_text())
FOOTER_Y = float(CFG["geometry"]["footer_y"])
SKIP = set(CFG.get("skip_pages", []))
FIXES = [(re.compile(a), b) for a, b in CFG.get("ocr_fixes", [])]

figs_path = Path(args.epub).with_suffix(".figs.json")
FIGS = json.loads(figs_path.read_text()) if figs_path.exists() else {}
if not FIGS:
    print(f"warning: no {figs_path.name}; figure labels will look 'missing'")


def norm(s):
    s = s.replace("ﬁ", "fi").replace("ﬂ", "fl")
    for pat, rep in FIXES:
        s = pat.sub(rep, s)
    return re.sub(r"[^a-z0-9]", "", s.lower())


z = zipfile.ZipFile(args.epub)
buf = [
    " ".join(etree.fromstring(z.read(n)).itertext())
    for n in z.namelist()
    if n.endswith(".xhtml")
]
epub_norm = norm(" ".join(buf))

doc = fitz.open(CFG["pdf"])
missing, checked = [], 0
for pno in range(len(doc)):
    if pno + 1 in SKIP:
        continue
    boxes = FIGS.get(str(pno + 1), [])
    for b in doc[pno].get_text("dict")["blocks"]:
        if b["type"] != 0:
            continue
        for ln in b["lines"]:
            t = "".join(s["text"] for s in ln["spans"]).strip()
            x0, y0, x1, y1 = ln["bbox"]
            if y0 >= FOOTER_Y:
                continue
            inside = any(
                min(f[2], x1) - max(f[0], x0) > 0.35 * (x1 - x0)
                and min(f[3], y1) - max(f[1], y0) > 0.35 * (y1 - y0)
                for f in boxes
            )
            if inside:
                continue
            words = t.split()
            if len(words) < 5:
                continue
            # probe the middle of the line: the ends get reflowed by
            # hyphen-joining and page-bridging
            probe = norm(" ".join(words[2:-1] if len(words) > 5 else words[1:]))
            if len(probe) < 12:
                continue
            checked += 1
            if probe not in epub_norm:
                missing.append((pno + 1, round(y0, 1), t))

print(f"lines checked: {checked}")
print(f"MISSING: {len(missing)}")
for pno, y, t in missing[:40]:
    print(f"  p{pno} y0={y}: {t[:80]}")
sys.exit(1 if missing else 0)
