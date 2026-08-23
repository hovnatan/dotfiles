# /// script
# requires-python = ">=3.11"
# dependencies = ["pymupdf", "numpy", "scipy", "pillow"]
# ///
"""Convert the OCR'd scan of 'Technical Behavioral Interview' into a reflowable EPUB.

Text comes from the OCRmyPDF text layer; structure (headings / lists / paragraphs)
is recovered from geometry, and diagrams are cropped out of the page images.
"""

import argparse
import html
import json
import io
import re
import uuid
import zipfile
from pathlib import Path

import fitz
import numpy as np
from PIL import Image
from scipy import ndimage

ap = argparse.ArgumentParser(description="Build a reflowable EPUB from an OCR'd book scan.")
ap.add_argument("config", help="book.json from calibrate.py")
ap.add_argument("-o", "--out", default="out.epub")
args = ap.parse_args()

CFG = json.loads(Path(args.config).read_text())
PDF = Path(CFG["pdf"])
COVER_JPEG = Path(CFG["cover"]) if CFG.get("cover") else None
OUT = Path(args.out)

G = CFG["geometry"]
COL_X0, COL_X1 = float(G["col_x0"]), float(G["col_x1"])
FOOTER_Y = float(G["footer_y"])       # measured, never guessed -- see calibrate.py
HEADING_MIN = float(G["heading_min"])
FIG_DPI = 300

TITLE = CFG.get("title") or PDF.stem
SUBTITLE = CFG.get("subtitle", "")
AUTHOR = CFG.get("author", "")
PUBLISHER = CFG.get("publisher", "")
LANG = CFG.get("language", "en")

SKIP_PAGES = set(CFG.get("skip_pages", []))
PART_PAGES = set(CFG.get("text_only_pages", []))   # big type, but real text
NO_FIG_PAGES = set(CFG.get("no_fig_pages", []))
KNOWN_HEADINGS = tuple(CFG.get("known_headings", []))
OCR_FIXES = [(re.compile(a), b) for a, b in CFG.get("ocr_fixes", [])]

_doc0 = fitz.open(PDF)
NPAGES = len(_doc0)


def build_sections():
    """Sections come from the PDF outline, plus any front_matter in the config.
    Page ranges run to the next section.

    The outline is NOT automatic: it exists only because a toc.txt was written by
    hand and piped into pdftocio. See propose_toc.py to draft one.
    """
    entries = []
    for _lvl, title, pg in _doc0.get_toc():
        if pg in SKIP_PAGES or not (1 <= pg <= NPAGES):
            continue
        entries.append({"title": title, "first": pg, "outline": True})
    for fm in CFG.get("front_matter", []):
        entries.append({
            "title": fm["title"], "first": int(fm["first"]),
            "last": int(fm.get("last", 0)) or None, "outline": False,
        })
    if not entries:
        raise SystemExit(
            "no sections: this PDF has no outline.\n"
            "The outline is not automatic -- it comes from a hand-written toc.txt:\n"
            "  propose_toc.py <pdf> --book book.json > toc.txt   # then EDIT it\n"
            "  pdftocio out_ocr.pdf < toc.txt\n"
            "or list the sections in front_matter in book.json."
        )

    entries.sort(key=lambda e: e["first"])
    last_page = max(p for p in range(1, NPAGES + 1) if p not in SKIP_PAGES)
    out = []
    for k, e in enumerate(entries):
        end = e.get("last")
        if not end:
            end = (entries[k + 1]["first"] - 1) if k + 1 < len(entries) else last_page
        if end < e["first"]:
            continue
        sid = f"sec{k + 1:02d}"
        out.append((sid, e["title"], e["first"], end, e["outline"]))
    return out


SECTIONS_FULL = build_sections()
SECTIONS = [(sid, t, a, b) for sid, t, a, b, _o in SECTIONS_FULL]

# Pages that open an outline section: their title line is OCR'd through a
# decorative icon/badge, so drop it and use the outline's title instead.
CHAPTER_OPENER = {a: sid for sid, _t, a, _b, outline in SECTIONS_FULL if outline}

BULLET_RE = re.compile(r"^\s*[-•·*+«»¢—–~e©●▪∙.,]{1,2}\s+")
NUM_RE = re.compile(r"^\s*(\d{1,2})[.)]\s+")

# Recurring section headings. Each is printed with a small icon that OCR turns
# into junk ("oll Key Signals", "F Red Flags", "@ Interview Questions", ...),
# so we strip any short prefix sitting in front of one of these.
KNOWN_HEADINGS = (
    "Key Signals",
    "Key Takeaways",
    "Red Flags",
    "Pro Tips",
    "Interview Questions",
    "If Examples",
    "The Essence of",
    "Mentoring People",
    "When Developing Others",
    "Cultural and Organizational",
    "Common Pitfalls",
)


def fix_heading(t):
    t = re.sub(r'^[^\w"“(]+\s*', "", t)  # leading @ ® & « © {> ...
    m = re.match(r"^(\S{1,4})\s+(.*)$", t)
    if m and m.group(2).startswith(KNOWN_HEADINGS):
        return m.group(2)
    return t


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def is_prose(ln):
    """A full-width line in the text column is body copy, never part of a figure."""
    return (ln["x1"] - ln["x0"]) > 0.55 * (COL_X1 - COL_X0) and 58 <= ln["x0"] <= 90


def clean(t):
    t = t.replace("ﬁ", "fi").replace("ﬂ", "fl")
    for pat, rep in OCR_FIXES:  # e.g. OCR reads "AI" as "Al"
        t = pat.sub(rep, t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


STYLE_DPI = 300


def word_styles(page):
    """Recover bold/italic from the pixels.

    The OCR text layer is a single glyphless font, so it carries no styling, and
    Tesseract won't report any either (the LSTM engine emits none; the legacy
    engine's is noise). But the glyphs are right there in the scan: bold has
    thicker strokes, italic has slanted ones. Measure both per word.
    """
    scale = STYLE_DPI / 72.0
    pix = page.get_pixmap(dpi=STYLE_DPI, colorspace=fitz.csGRAY)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width)
    ink = img < 128

    shears = np.arange(-0.10, 0.46, 0.03)
    out = []
    for w in page.get_text("words"):
        x0, y0, x1, y1, txt = w[0], w[1], w[2], w[3], w[4]
        a, b = max(0, int(y0 * scale) - 1), int(y1 * scale) + 2
        c, d = max(0, int(x0 * scale) - 1), int(x1 * scale) + 2
        m = ink[a:b, c:d]

        if len(txt) < 3 or m.sum() < 30:
            out.append({"bbox": (x0, y0, x1, y1), "w": txt, "sw": None, "sl": None})
            continue

        # stroke thickness: 2 x mean distance-to-edge over the ink
        sw = 2.0 * ndimage.distance_transform_edt(m)[m].mean()

        # slant: the shear that best straightens stems into sharp columns.
        # Italic leans right, so its stems align under a positive shear.
        ys, xs = np.nonzero(m)
        yc = ys.mean()
        best, best_s = -1.0, 0.0
        for s in shears:
            xx = np.rint(xs + s * (ys - yc)).astype(np.int64)
            xx -= xx.min()
            hist = np.bincount(xx).astype(float)
            score = (hist**2).sum() / (hist.sum() ** 2)
            if score > best:
                best, best_s = score, s
        out.append({"bbox": (x0, y0, x1, y1), "w": txt, "sw": sw, "sl": best_s})

    known_sw = [o["sw"] for o in out if o["sw"] is not None]
    known_sl = [o["sl"] for o in out if o["sl"] is not None]
    if not known_sw:
        for o in out:
            o["b"] = o["i"] = False
        return out

    # Thresholds are relative to this page's own body type, so they survive
    # variations in scan darkness from page to page.
    bold_t = float(np.median(known_sw)) * 1.18
    ital_t = float(np.median(known_sl)) + 0.08
    for o in out:
        if o["sw"] is None:
            o["b"] = o["i"] = None  # unknown: too short to measure
        else:
            o["b"] = o["sw"] > bold_t
            o["i"] = o["sl"] > ital_t and not o["b"]
    return out


def get_lines(page, styles=None):
    swords = list(styles or [])
    out = []
    for b in page.get_text("dict")["blocks"]:
        if b["type"] != 0:
            continue
        for ln in b["lines"]:
            txt = "".join(s["text"] for s in ln["spans"]).strip()
            if not txt:
                continue
            x0, y0, x1, y1 = ln["bbox"]
            # "size" is the max span, which an OCR'd icon glyph can inflate
            # ("F Red Flags" -> 13.4 because of the "F"). "dsize" is the size of
            # the span carrying the most characters, i.e. the actual words.
            dom = max(ln["spans"], key=lambda s: len(s["text"]))

            # Words of this line, in reading order, carrying their style.
            toks = []
            for sw in swords:
                wx0, wy0, wx1, wy1 = sw["bbox"]
                cx, cy = (wx0 + wx1) / 2, (wy0 + wy1) / 2
                if x0 - 1 <= cx <= x1 + 1 and y0 - 1 <= cy <= y1 + 1:
                    toks.append({"w": sw["w"], "x": wx0, "b": sw["b"], "i": sw["i"]})
            toks.sort(key=lambda t: t["x"])
            fill_unknown(toks)
            for t in toks:
                t["w"] = clean(t["w"])
            toks = [t for t in toks if t["w"]]
            if not toks:  # never let a line lose its words
                toks = [{"w": w, "x": x0, "b": False, "i": False}
                        for w in clean(txt).split()]

            out.append({
                "text": txt,
                "size": max(s["size"] for s in ln["spans"]),
                "dsize": dom["size"],
                "toks": toks,
                "x0": x0, "y0": y0, "x1": x1, "y1": y1,
            })
    out.sort(key=lambda ln: (round(ln["y0"] / 3), ln["x0"]))
    return out


def fill_unknown(toks):
    """Short words ("to", "of") are too small to measure. Let them inherit, so
    an italic phrase stays one run instead of fragmenting around them."""
    for k, tk in enumerate(toks):
        if tk["b"] is not None:
            continue
        prev = next((t for t in reversed(toks[:k]) if t["b"] is not None), None)
        nxt = next((t for t in toks[k + 1:] if t["b"] is not None), None)
        if prev and nxt and (prev["b"], prev["i"]) == (nxt["b"], nxt["i"]):
            tk["b"], tk["i"] = prev["b"], prev["i"]
        else:
            tk["b"], tk["i"] = False, False




def find_figures(page, lines, pno):
    """Ink the OCR word boxes don't explain -> diagram regions (PDF points)."""
    pix = page.get_pixmap(dpi=72, colorspace=fitz.csGRAY)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width)
    ink = img < 128
    if not ink.any():
        return []

    # Tesseract reads a diagram's icons as huge "text" ("ny", "Da", "£2" at
    # 25-30pt), which would mask their ink out of the graphics layer. Keep that
    # ink -- but only for gibberish like that, never for real words: some real
    # headings ("Key Takeaways") are also set large, and must stay text.
    artwork = [
        ln for ln in lines
        if ln["dsize"] >= 13
        and ln["y1"] <= FOOTER_Y
        and not re.search(r"[A-Za-z]{3,}", ln["text"])  # no real word -> a glyph
        and not (ln["y0"] < 140 and ln["x0"] < 100)
        and pno not in PART_PAGES
    ]

    def is_artwork(x0, y0, x1, y1):
        return any(
            x0 >= a["x0"] - 2 and x1 <= a["x1"] + 2
            and y0 >= a["y0"] - 2 and y1 <= a["y1"] + 2
            for a in artwork
        )

    mask = ink.copy()
    for w in page.get_text("words"):
        x0, y0, x1, y1 = w[:4]
        if is_artwork(x0, y0, x1, y1):
            continue
        mask[max(0, int(y0) - 2):int(y1) + 3, max(0, int(x0) - 2):int(x1) + 3] = False
    mask[int(FOOTER_Y):, :] = False

    # Dilate only to group strokes into blobs -- but always measure ink on the
    # raw mask. Measuring the dilated mask inflates a single stray speck to ~81
    # px, which sails past any sane threshold and fabricates phantom figures.
    dil = ndimage.binary_dilation(mask, np.ones((9, 9)))
    lab, n = ndimage.label(dil)
    if n == 0:
        return []

    # Keep even tiny blobs here: the connector arrows and rules inside a diagram
    # are what bridge its separate parts into one figure.
    boxes = []
    for sl in ndimage.find_objects(lab):
        ys, xs = sl
        sub = mask[sl]                       # raw ink, not the dilated blob
        if int(sub.sum()) < 25:
            continue
        rr = np.where(sub.any(axis=1))[0]
        cc = np.where(sub.any(axis=0))[0]
        rh, rw = rr[-1] - rr[0] + 1, cc[-1] - cc[0] + 1

        # A long thin stroke on its own is a printed rule -- a section divider or
        # a heading underline -- not artwork. Left in, it seeds a figure that
        # then swallows the very heading it was underlining.
        if rh <= 5 and rw >= 60:
            continue

        x0 = xs.start + cc[0] - 4.0
        y0 = ys.start + rr[0] - 4.0
        boxes.append([x0, y0, x0 + rw + 8.0, y0 + rh + 8.0])

    def merge(bs, pad):
        changed = True
        while changed:
            changed = False
            for i in range(len(bs)):
                for j in range(i + 1, len(bs)):
                    a, b = bs[i], bs[j]
                    if (a[0] < b[2] + pad and b[0] < a[2] + pad
                            and a[1] < b[3] + pad and b[1] < a[3] + pad):
                        bs[i] = [min(a[0], b[0]), min(a[1], b[1]),
                                 max(a[2], b[2]), max(a[3], b[3])]
                        bs.pop(j)
                        changed = True
                        break
                if changed:
                    break
        return bs

    boxes = merge(boxes, 18)                                    # strokes -> parts
    boxes = merge(boxes, 45)                                    # parts -> diagram

    # Keep clusters with real ink in them. Judging *size* here would be wrong:
    # a diagram's seed can be just its icon row, and it only reaches full size
    # after it absorbs its captions below. So gate on ink now, size later.
    def ink_in(b):
        x0 = max(0, int(b[0]))
        y0 = max(0, int(b[1]))
        x1 = min(pix.width, int(b[2]))
        y1 = min(pix.height, int(b[3]))
        return int(mask[y0:y1, x0:x1].sum()) if x1 > x0 and y1 > y0 else 0

    boxes = [b for b in boxes if ink_in(b) >= 300]

    # Absorb the diagram's own labels, until stable. A label either sits inside
    # the graphics (a box label) or just underneath them (a caption under an
    # icon). Headings (>=HEADING_MIN) are never absorbed -- they belong to the text.
    for _ in range(6):
        grew = False
        for f in boxes:
            for ln in lines:
                if ln["y1"] > FOOTER_Y or is_prose(ln):
                    continue
                lw = ln["x1"] - ln["x0"]
                lh = ln["y1"] - ln["y0"]
                ox = min(f[2], ln["x1"]) - max(f[0], ln["x0"])
                oy = min(f[3], ln["y1"]) - max(f[1], ln["y0"])
                inside = ox > 0.35 * lw and oy > 0.35 * lh
                vgap = max(f[1] - ln["y1"], ln["y0"] - f[3])
                # A caption sits just outside the graphics. Paragraph tails sit
                # there too ("it lacked."), so require it to look like a label:
                # a label never ends in sentence punctuation.
                caption = (
                    ln["size"] < HEADING_MIN
                    and ox > 0.5 * lw
                    and vgap <= 16  # negative == it already overlaps the box
                    and not ln["text"].rstrip().endswith((".", "?", "!", "”", '"'))
                )
                if inside or caption:
                    nf = [min(f[0], ln["x0"] - 3), min(f[1], ln["y0"] - 3),
                          max(f[2], ln["x1"] + 3), max(f[3], ln["y1"] + 3)]
                    if nf != f:
                        f[:] = nf
                        grew = True
        boxes = merge(boxes, 12)
        if not grew:
            break

    # Now that each figure includes its captions, judge whether it is one.
    def covers_text(b):
        for ln in lines:
            ox = min(b[2], ln["x1"]) - max(b[0], ln["x0"])
            oy = min(b[3], ln["y1"]) - max(b[1], ln["y0"])
            if ox > 0.5 * (ln["x1"] - ln["x0"]) and oy > 0.5 * (ln["y1"] - ln["y0"]):
                return True
        return False

    # A wide, short band of ink that OCR produced *no* text for is a stylized
    # heading Tesseract couldn't read ("Key Takeaways" on p104). Keep it as an
    # image -- otherwise the heading vanishes from the book entirely.
    boxes = [
        b for b in boxes
        if ((b[2] - b[0]) > 90 and (b[3] - b[1]) > 45)
        or ((b[2] - b[0]) > 90 and (b[3] - b[1]) >= 16
            and ink_in(b) >= 400 and not covers_text(b))
    ]

    # A chapter opener's number badge is solid black and seeds a "figure" that
    # drags the chapter title in with it. The title is already emitted as <h1>.
    if pno in CHAPTER_OPENER:
        boxes = [b for b in boxes if b[3] >= 175]
    if pno in NO_FIG_PAGES:
        boxes = []
    return boxes


def in_fig(ln, figs):
    if is_prose(ln):
        return False  # never lose body copy to a figure box
    for f in figs:
        ox = min(f[2], ln["x1"]) - max(f[0], ln["x0"])
        oy = min(f[3], ln["y1"]) - max(f[1], ln["y0"])
        if ox > 0.35 * (ln["x1"] - ln["x0"]) and oy > 0.35 * (ln["y1"] - ln["y0"]):
            return True
    return False


def is_footer(ln):
    # Purely positional: the lowest body line in the book sits at y0=613.1, the
    # highest running foot at y0=627.9. Anything below the line is a footer.
    return ln["y0"] >= FOOTER_Y


# ---------------------------------------------------------------- pass 1: scan
doc = fitz.open(PDF)
pages = {}
print(f"scanning {len(doc)} pages ...")
for pno in range(len(doc)):
    page = doc[pno]
    lines = get_lines(page, word_styles(page))
    figs = find_figures(page, lines, pno + 1)
    body = [ln for ln in lines if not is_footer(ln) and not in_fig(ln, figs)]

    # Drop the chapter-opener title + number badge; we use the canonical title.
    if (pno + 1) in CHAPTER_OPENER:
        big = HEADING_MIN * 1.4  # the decorative chapter title, icon and all
        body = [ln for ln in body if not (ln["size"] >= big and ln["y0"] < 140)]

    pages[pno + 1] = {"lines": body, "figs": figs}

# Sidecar for the verifier: the exact figure regions we rasterized.
import json  # noqa: E402

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.with_suffix(".figs.json").write_text(
    json.dumps({p: v["figs"] for p, v in pages.items()})
)

# Vocabulary of genuinely hyphenated compounds, so we only remove hyphens that
# OCR introduced at a line break (keep "trade-offs", drop "invest-\nigation").
hyph_vocab = set()
for p in pages.values():
    for ln in p["lines"]:
        for w in ln["text"].split():
            w = w.strip('.,;:!?"“”()').lower()
            if "-" in w[1:-1] and re.fullmatch(r"[a-z]+(-[a-z]+)+", w):
                hyph_vocab.add(w)
print(f"hyphenated-compound vocabulary: {len(hyph_vocab)} words")


def is_punct(s):
    return bool(s) and len(s) <= 3 and not any(c.isalnum() for c in s)


def merge_chunks(chunks):
    """Merge lines of styled words into one flowing run, undoing line-break
    hyphenation. Chunks are lists of word tokens, so styling survives."""
    chunks = [[dict(t) for t in c if t["w"].strip()] for c in chunks]
    chunks = [c for c in chunks if c]

    # OCR sometimes emits a stray closing quote as its own line, landing between
    # "obvi-" and "ous." and wrecking the hyphen join. Move it past the join.
    i = 0
    while i + 2 < len(chunks):
        if (chunks[i][-1]["w"].endswith("-")
                and len(chunks[i + 1]) == 1 and is_punct(chunks[i + 1][0]["w"])):
            chunks[i + 1], chunks[i + 2] = chunks[i + 2], chunks[i + 1]
            i += 2
        else:
            i += 1

    out = []
    for ch in chunks:
        if not out:
            out.extend(ch)
            continue
        if len(ch) == 1 and is_punct(ch[0]["w"]):
            out[-1]["w"] += ch[0]["w"]  # no space before stray punctuation
            continue
        if out[-1]["w"].endswith("-"):
            stem = out[-1]["w"][:-1]
            head = ch[0]["w"]
            nxt = head.strip('.,;:!?"“”()')
            base = stem.strip('“”"()')
            key = (base + "-" + nxt).lower()
            out[-1]["w"] = (stem + head) if key not in hyph_vocab else (stem + "-" + head)
            out.extend(ch[1:])
        else:
            out.extend(ch)
    return out


def toks_plain(toks):
    return " ".join(t["w"] for t in toks)


def toks_html(toks):
    """Emit the run, wrapping maximal same-style spans in <strong>/<em>."""
    parts, cur = [], (False, False)
    for k, t in enumerate(toks):
        sep = "" if k == 0 else " "
        st = (bool(t["b"]), bool(t["i"]))
        if st != cur:
            if cur[1]:
                parts.append("</em>")
            if cur[0]:
                parts.append("</strong>")
            parts.append(sep)
            if st[0]:
                parts.append("<strong>")
            if st[1]:
                parts.append("<em>")
            cur = st
        else:
            parts.append(sep)
        parts.append(esc(t["w"]))
    if cur[1]:
        parts.append("</em>")
    if cur[0]:
        parts.append("</strong>")
    return "".join(parts)


def join_lines(chunks):
    return toks_plain(merge_chunks(chunks))


# ------------------------------------------------------- pass 2: build blocks
def classify(pno, lines, figs):
    """Turn one page's lines+figures into ordered blocks."""
    items = []
    for ln in lines:
        items.append(("line", ln["y0"], ln))
    for f in figs:
        items.append(("fig", f[1], f))
    items.sort(key=lambda it: it[1])

    blocks = []
    for kind, _, obj in items:
        if kind == "fig":
            blocks.append({"type": "fig", "page": pno, "bbox": obj})
            continue

        ln = obj
        t = clean(ln["text"])
        if not t:
            continue
        width = ln["x1"] - ln["x0"]
        prev = blocks[-1] if blocks else None
        gap = 99.0
        if prev and prev.get("y1") is not None:
            gap = ln["y0"] - prev["y1"]

        # heading: larger type, short line, preceded by whitespace, unpunctuated.
        # "?" is allowed -- many section headings are questions ("What Does It
        # Mean to Deliver?").
        is_head = (
            ln["size"] >= HEADING_MIN
            and width < 0.90 * (COL_X1 - COL_X0)
            and gap > 7.5
            and not t.rstrip().endswith((".", ",", ";", ":", "”", '"'))
            and len(t) > 3
            and ln["x0"] < 100
        )
        if is_head:
            blocks.append({"type": "h", "text": fix_heading(t), "y1": ln["y1"]})
            continue

        mnum = NUM_RE.match(ln["text"])
        mbul = BULLET_RE.match(ln["text"])
        indent = ln["x0"]

        # list item: marker + indented from the text column
        if (mbul or mnum) and indent > 66.5 and width < (COL_X1 - COL_X0):
            body = strip_marker(ln["toks"], (mnum or mbul).group(0))
            blocks.append({
                "type": "li",
                "ordered": bool(mnum),
                "chunks": [body],
                "y1": ln["y1"],
                "x0": indent,
            })
            continue

        # Continuation of the current list item. Some lists hang the wrap under
        # the text (x0~85), but the "Key Takeaways" lists set it flush with the
        # bullet itself (x0~75), so test against the item's own indent rather
        # than a fixed column.
        if (
            prev
            and prev["type"] == "li"
            and gap < 8
            and not (mbul or mnum)
            and indent >= prev["x0"] - 3
        ):
            prev["chunks"].append(ln["toks"])
            prev["y1"] = ln["y1"]
            continue

        # paragraph: continue the previous one, or start a new one
        if prev and prev["type"] == "p" and gap < 8:
            prev["chunks"].append(ln["toks"])
            prev["y1"] = ln["y1"]
        else:
            blocks.append({"type": "p", "chunks": [ln["toks"]], "y1": ln["y1"]})
    return blocks


def strip_marker(toks, marker):
    """Drop the leading bullet / number token(s) from a list item."""
    mk = "".join(marker.split())
    out = [dict(t) for t in toks]
    got = ""
    while out and len(got) < len(mk):
        got += out[0]["w"]
        out.pop(0)
    return out


def bridge(blocks):
    """Rejoin a paragraph or list item that was split across a page break.

    The continuation always arrives as a plain "p" (it has no bullet of its
    own), so it must be able to merge back into a "li" as well as a "p" --
    and it may be mid-word, when the split fell on a hyphen.
    """
    out = []
    for b in blocks:
        if b.get("cross") and b["type"] == "p" and out and out[-1]["type"] in ("p", "li"):
            prev = out[-1]
            tail = join_lines(prev["chunks"]).rstrip()
            head = join_lines(b["chunks"]).lstrip()
            unfinished = not re.search(r"""[.!?:”"’)]$""", tail)
            if tail and head and (tail.endswith("-") or (unfinished and head[:1].islower())):
                prev["chunks"] = prev["chunks"] + b["chunks"]
                continue
        out.append(b)
    return out


# ------------------------------------------------------------ pass 3: emit
figdir_imgs = {}


def crop_figure(pno, bbox):
    key = (pno, tuple(round(v, 1) for v in bbox))
    if key in figdir_imgs:
        return figdir_imgs[key]
    page = doc[pno - 1]
    rect = fitz.Rect(*bbox) & page.rect
    pix = page.get_pixmap(clip=rect, dpi=FIG_DPI, colorspace=fitz.csGRAY)
    im = Image.frombytes("L", (pix.width, pix.height), pix.samples)
    # downscale a touch: 300dpi bitonal is sharper than any Kindle needs
    im.thumbnail((1400, 1800), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    name = f"fig{len(figdir_imgs) + 1:03d}.png"
    figdir_imgs[key] = (name, buf.getvalue())
    return figdir_imgs[key]


def esc(s):
    return html.escape(s, quote=False)


def is_junk(t):
    """OCR noise scraped off a diagram's strokes, e.g. 's>«".."....'."""
    letters = sum(c.isalpha() for c in t)
    return letters < 0.45 * len(t) and not re.search(r"[A-Za-z]{4,}", t)


def render(sid, title, p0, p1):
    blocks = []
    for pno in range(p0, p1 + 1):
        if pno in SKIP_PAGES:
            continue
        pg = pages.get(pno)
        if not pg:
            continue
        bs = classify(pno, pg["lines"], pg["figs"])
        if bs and blocks:
            bs[0]["cross"] = True
        blocks.extend(bs)
    blocks = bridge(blocks)

    parts = [f"<h1>{esc(title)}</h1>"]
    open_list = None
    for b in blocks:
        if b["type"] != "li" and open_list:
            parts.append(f"</{open_list}>")
            open_list = None

        if b["type"] == "fig":
            name, _ = crop_figure(b["page"], b["bbox"])
            parts.append(
                f'<div class="fig"><img src="../images/{name}" alt="Diagram"/></div>'
            )
        elif b["type"] == "h":
            parts.append(f"<h2>{esc(b['text'])}</h2>")
        elif b["type"] == "li":
            want = "ol" if b["ordered"] else "ul"
            if open_list != want:
                if open_list:
                    parts.append(f"</{open_list}>")
                parts.append(f"<{want}>")
                open_list = want
            toks = merge_chunks(b["chunks"])
            if toks:
                parts.append(f"<li>{toks_html(toks)}</li>")
        else:
            toks = merge_chunks(b["chunks"])
            if toks and not is_junk(toks_plain(toks)):
                parts.append(f"<p>{toks_html(toks)}</p>")
    if open_list:
        parts.append(f"</{open_list}>")

    body = "\n".join(parts)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head><title>{esc(title)}</title>
<link rel="stylesheet" type="text/css" href="../styles/main.css"/></head>
<body>
{body}
</body>
</html>
"""


docs = []
for sid, title, p0, p1 in SECTIONS:
    docs.append((sid, title, render(sid, title, p0, p1)))
    print(f"  {sid:<15} p{p0}-{p1}")

print(f"figures cropped: {len(figdir_imgs)}")

# ------------------------------------------------------------ pass 4: package
CSS = """@page { margin: 5pt; }
body { margin: 0 1em; line-height: 1.45; widows: 2; orphans: 2; }
h1 { font-size: 1.6em; margin: 1.2em 0 0.8em; line-height: 1.25;
     page-break-before: always; page-break-after: avoid; }
h2 { font-size: 1.15em; margin: 1.4em 0 0.4em; line-height: 1.3;
     page-break-after: avoid; }
p  { margin: 0 0 0.65em; text-align: justify; text-indent: 0; }
ul, ol { margin: 0.5em 0 0.9em 1.1em; padding: 0; }
li { margin: 0 0 0.35em; text-align: left; }
div.fig { margin: 1.1em 0; text-align: center; page-break-inside: avoid; }
div.fig img { max-width: 100%; height: auto; }
img.cover { max-width: 100%; height: auto; }
"""

# Cover: prefer the original colour scan if given, else rasterize page 1.
cover_bytes = None
if COVER_JPEG and COVER_JPEG.exists():
    cover_img = Image.open(COVER_JPEG).convert("RGB")
elif NPAGES:
    cpix = doc[0].get_pixmap(dpi=150)
    cover_img = Image.frombytes("RGB", (cpix.width, cpix.height), cpix.samples)
else:
    cover_img = None
if cover_img is not None:
    cover_img.thumbnail((1600, 2400), Image.LANCZOS)
    cbuf = io.BytesIO()
    cover_img.save(cbuf, "JPEG", quality=86, optimize=True)
    cover_bytes = cbuf.getvalue()

COVER_XHTML = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head><title>Cover</title>
<link rel="stylesheet" type="text/css" href="../styles/main.css"/></head>
<body><div class="fig"><img class="cover" src="../images/cover.jpg" alt="Cover"/></div></body>
</html>
"""

TITLE_XHTML = f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head><title>{TITLE}</title>
<link rel="stylesheet" type="text/css" href="../styles/main.css"/></head>
<body><h1>{TITLE}</h1><p><em>{SUBTITLE}</em></p><p>{AUTHOR}</p><p>{PUBLISHER}</p></body>
</html>
"""

bid = f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, 'bytebytego-tbi')}"

manifest, spine, navlis = [], [], []
manifest.append('<item id="css" href="styles/main.css" media-type="text/css"/>')
if cover_bytes:
    manifest.append('<item id="cover-img" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>')
    manifest.append('<item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>')
manifest.append('<item id="titlepage" href="text/titlepage.xhtml" media-type="application/xhtml+xml"/>')
manifest.append('<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>')
if cover_bytes:
    spine.append('<itemref idref="cover"/>')
spine += ['<itemref idref="titlepage"/>', '<itemref idref="nav"/>']

for name, _ in figdir_imgs.values():
    manifest.append(f'<item id="{name[:-4]}" href="images/{name}" media-type="image/png"/>')

for sid, title, _ in docs:
    manifest.append(f'<item id="{sid}" href="text/{sid}.xhtml" media-type="application/xhtml+xml"/>')
    spine.append(f'<itemref idref="{sid}"/>')
    navlis.append(f'<li><a href="text/{sid}.xhtml">{esc(title)}</a></li>')

manifest_s = "\n    ".join(manifest)
spine_s = "\n    ".join(spine)
nav_s = "\n".join(navlis)

OPF = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">{bid}</dc:identifier>
    <dc:title>{TITLE}</dc:title>
    <dc:creator>{AUTHOR}</dc:creator>
    <dc:publisher>{PUBLISHER}</dc:publisher>
    <dc:language>{LANG}</dc:language>
    <dc:description>{SUBTITLE}. Converted from a scanned PDF via OCR.</dc:description>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    {manifest_s}
  </manifest>
  <spine>
    {spine_s}
  </spine>
</package>
"""

NAV = f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"
      xml:lang="en" lang="en">
<head><title>Contents</title>
<link rel="stylesheet" type="text/css" href="styles/main.css"/></head>
<body>
<nav epub:type="toc" id="toc"><h1>Contents</h1>
<ol>
{nav_s}
</ol>
</nav>
</body>
</html>
"""

CONTAINER = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

OUT.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(OUT, "w") as z:
    z.writestr("mimetype", "application/epub+zip", zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", CONTAINER, zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/content.opf", OPF, zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/nav.xhtml", NAV, zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/styles/main.css", CSS, zipfile.ZIP_DEFLATED)
    if cover_bytes:
        z.writestr("OEBPS/images/cover.jpg", cover_bytes, zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/text/cover.xhtml", COVER_XHTML, zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/text/titlepage.xhtml", TITLE_XHTML, zipfile.ZIP_DEFLATED)
    for name, data in figdir_imgs.values():
        z.writestr(f"OEBPS/images/{name}", data, zipfile.ZIP_DEFLATED)
    for sid, _, xhtml in docs:
        z.writestr(f"OEBPS/text/{sid}.xhtml", xhtml, zipfile.ZIP_DEFLATED)

print(f"\nwrote {OUT}  ({OUT.stat().st_size / 1e6:.1f} MB)")
