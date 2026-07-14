# /// script
# requires-python = ">=3.11"
# dependencies = ["pymupdf", "pillow"]
# ///
"""Look at the figures. Both automated checks are blind here.

Coverage and lint both ignore anything inside a figure box by design, so a
phantom figure -- or one that swallowed a heading -- is invisible to them. The
only check is your eyes.

  figsheet.py out.epub -o figs.png              contact sheet of every figure
  figsheet.py book.json -o pages.png -p 18,45   figure boxes drawn on pages
"""

import argparse
import io
import json
import math
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument("target", help="the .epub, or book.json to overlay boxes on pages")
ap.add_argument("-o", "--out", default="figs.png")
ap.add_argument("-p", "--pages", default="", help="pages to overlay, e.g. 18,45,112")
args = ap.parse_args()

if args.target.endswith(".epub"):
    z = zipfile.ZipFile(args.target)
    names = sorted(n for n in z.namelist() if "/images/fig" in n)
    if not names:
        raise SystemExit("no figures in this epub")
    cols, tw, th = 8, 210, 185
    rows = math.ceil(len(names) / cols)
    sheet = Image.new("RGB", (cols * tw, rows * th), "#ddd")
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        im = Image.open(io.BytesIO(z.read(n))).convert("RGB")
        im.thumbnail((tw - 10, th - 22))
        x, y = (i % cols) * tw + 5, (i // cols) * th + 16
        sheet.paste(im, (x, y))
        d.text((x, y - 13), Path(n).stem, fill="red")
    sheet.save(args.out)
    print(f"{len(names)} figures -> {args.out}")
    print("check for: phantom figures (a rule or stray speck), figures that")
    print("swallowed a heading, and diagrams cut in half.")
else:
    import fitz

    cfg = json.loads(Path(args.target).read_text())
    figs_path = Path(args.target).with_suffix(".figs.json")
    figs = json.loads(figs_path.read_text()) if figs_path.exists() else {}
    doc = fitz.open(cfg["pdf"])
    pages = [int(x) for x in args.pages.split(",") if x.strip()] or [
        int(p) for p in sorted(figs, key=int)
    ]
    scale, cols = 1.4, min(5, len(pages))
    tw, th = int(doc[0].rect.width * 0.62), int(doc[0].rect.height * 0.62)
    rows = math.ceil(len(pages) / cols)
    sheet = Image.new("RGB", (cols * tw, rows * (th + 14)), "#ccc")
    sd = ImageDraw.Draw(sheet)
    for i, pno in enumerate(pages):
        pix = doc[pno - 1].get_pixmap(dpi=int(72 * scale), colorspace=fitz.csGRAY)
        im = Image.frombytes("L", (pix.width, pix.height), pix.samples).convert("RGB")
        d = ImageDraw.Draw(im)
        for f in figs.get(str(pno), []):
            d.rectangle([f[0] * scale, f[1] * scale, f[2] * scale, f[3] * scale],
                        outline=(255, 0, 0), width=3)
        im.thumbnail((tw - 6, th - 6))
        x, y = (i % cols) * tw + 3, (i // cols) * (th + 14) + 12
        sheet.paste(im, (x, y))
        sd.text((x, y - 11), f"p{pno}: {len(figs.get(str(pno), []))} figs", fill=(200, 0, 0))
    sheet.save(args.out)
    print(f"{len(pages)} pages -> {args.out}")
