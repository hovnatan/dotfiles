#!/usr/bin/env -S uv run --managed-python --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy>=2", "pillow>=11", "scipy>=1.13"]
# ///
# --managed-python: under Nix's python3 on Linux the numpy wheel fails to
# load (libstdc++.so.6 is on no path its loader searches).
r"""Revise the content boxes of a ScanTailor Advanced project, a model judging.

    scantailor_boxes.py <book>.ScanTailor [--pages N ...] [--run-dir <dir>]
                        [--out <file>]

For a project saved after Select Content. ScanTailor's automatic box often
takes in a scan shadow, a scanner line or a reader's handwriting, or leaves
out a page number. Here the box is rebuilt from the page's ink:

    <book>.ScanTailor, and the page images it names
      |  every region of ink on each page, deskewed as ScanTailor has it,
      v  boxed and numbered on a preview        regions.jsonl, previews/
    one `claude -p` call a page: which numbers are junk, which mix junk
      |  with content, which it cannot tell     verdicts.jsonl, calls/
      v
    a page with a mixed region, cut into finer regions and judged again
      |                                         *-fine.jsonl, *-fine/
      v
    box = what bounds the regions not judged junk; a page is rewritten
      |  when an edge moves more than TOLERANCE_MM          report.tsv
      v
    <book>_revised.ScanTailor (or --out), every page's box set to manual,
    and sheets to check by eye: compare/ (old box red, new green), junk/

The revised project's last two steps are set to change nothing but
geometry, so that running Margins and then Output there gives each page
deskewed, blank outside its box, its pixels otherwise as scanned:

    Margins   0 mm on every side; "Match size with other pages" on, both
              modes Original: every page comes out the size of the
              largest, its content where it stood on the scanned page
    Output    Color / Grayscale (nothing binarised, so nothing despeckled
              or smoothed), at the scan's own dpi; "Fill margins" on, so
              what lies outside the box takes the page's background
              colour; no equalised illumination, dewarping or split output

The model names regions, never coordinates: every edge comes from pixels.

The run's folder is <book's folder>/.logs/<UTC time>_content_boxes/, or
--run-dir to carry one on: a page prepared or judged is not done again, so
a run that stopped, or a pilot (--pages, which stops after the first
judging), is resumed by naming its folder. To correct a verdict, write
overrides.jsonl in the run's folder and run again with --run-dir:

    {"page": 19, "pass": "first", "junk": [11]}

"pass" says whose region numbers these are: "first" (previews/) or "fine"
(previews-fine/). An override wins over both passes.

A page ScanTailor cut at Split Pages is taken whole again: its automatic
cuts slice content often enough, and what the cut meant to drop is junk the
model drops anyway. Not handled, and refused by name: a two-page spread, an
image turned at Fix Orientation, a scan under 100 dpi.

About $0.033 a page at list price (Sonnet 5.5, medium effort; 275 pages
took 2.5 minutes at 8 calls at a time). Needs claude and uv on PATH.
"""

# A script invoked by path, no license header.
# ruff: noqa: CPY001

import argparse
import csv
import json
import math
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None

MODEL = "claude-sonnet-5-5"
EFFORT = "medium"
ATTEMPTS = 3
COST_PER_PAGE_USD = 0.033

# A box edge has to move by more than this for the page to be rewritten:
# ScanTailor finds its box on a 150 dpi grid, this script on a 100 dpi one.
TOLERANCE_MM = 1.0
# The page outline this script works out may differ from the one stored in
# the project by this much; more means the coordinate mapping is wrong.
OUTLINE_SLACK_PX = 1.5
MIN_DPI = 100
# Ink darker than this counts. A JPEG's white is not clean, so its is higher.
INK_BELOW = 128
INK_BELOW_JPEG = 160
# Half-widths, in 100 dpi cells, of the box that joins ink into one region.
JOIN = (10, 7)
JOIN_FINE = (3, 2)
SPECK_MAX_INK_PX = 60
SPECK_MAX_CELLS = 6
PREVIEW_LONG_SIDE = 1500
COLOURS = ["#d00000", "#0057d9", "#008a2e", "#b000b0", "#c26a00", "#008b8b"]
# junk/ shows a junk region only when it is this far from every scan edge.
EDGE_MM = 5
MM_PER_INCH = 25.4
# The two judging passes, and what the name of each one's files ends in.
PASSES = {"first": "", "fine": "-fine"}
# The steps that keep an entry a page, beside Split Pages' one an image.
STEPS = ("deskew", "select-content", "page-layout", "output")

Polygon = list[tuple[float, float]]
Box = list[float]

SCHEMA = {
    "type": "object",
    "properties": {
        "junk": {"type": "array", "items": {"type": "integer"}},
        "mixed": {"type": "array", "items": {"type": "integer"}},
        "unsure": {"type": "array", "items": {"type": "integer"}},
        "note": {"type": "string"},
    },
    "required": ["junk", "mixed", "unsure", "note"],
    "additionalProperties": False,
}
SYSTEM = (
    "You judge scanned book pages. Look at the image you are pointed to and "
    "answer in the required structure."
)
PROMPT = """\
Read the image `{image}` (relative to the current directory) with the Read
tool, then judge it.

It is a scan of one page of a printed book. A script found every region of
ink and drew a coloured box around it, with a number tag at the box's
top-left corner (below the box when there is no room above). Say which
numbered regions are not part of the printed page.

Content, to keep: anything the publisher printed. Body text, headings, page
numbers (often one or two small digits alone near a top or bottom corner),
running heads, footnotes, captions, photographs, illustrations, diagrams
and charts with their labels, and rules or frame lines that belong to a
figure or separate sections.

Junk, to report:

- Scan shadows: dark wedges, smears or gradients, usually at a page edge or
  corner.
- Scanner lines: thin straight lines running along a page edge, often
  broken into several regions one above the other.
- Marks at the very edge of the image: dashes, slivers, fragments of the
  facing page.
- Specks, dust, punch holes, binding marks.
- Handwriting, pen marks or stamps added by a reader.

Mixed: a region whose own ink holds both content and junk joined together
(a shadow running into a diagram, a pen note touching a text line). A
region is not mixed merely because another region's box overlaps it.

Unsure: you cannot tell. Do not guess.

These are all the regions on this page. Use only these numbers; a tag can
be hidden behind another box, so find such a region by its position.
Positions and sizes are in millimetres from the image's top-left corner;
the image is {page_w} mm wide and {page_h} mm high.

{regions}

Answer with the lists `junk`, `mixed` and `unsure` (region numbers; a
region in none of them counts as content) and a `note` of one short phrase
naming what the junk is, or an empty string when there is none.
"""


class BoxError(Exception):
    """A state this script refuses to work past; the message says the fix."""


class Log:
    """UTC-stamped lines, to the run's events.log and to stdout, as written."""

    def __init__(self, run: Path) -> None:
        """Append to `run`/events.log."""
        self.file = (run / "events.log").open("a", buffering=1, encoding="utf-8")
        self.lock = threading.Lock()

    def note(self, message: str) -> None:
        """Write one line to the file and to stdout, whole whichever thread notes."""
        line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {message}\n"
        with self.lock:
            self.file.write(line)
            sys.stdout.write(line)
            sys.stdout.flush()


@dataclass
class Page:
    """One page of the project, as the first three steps left it."""

    number: int
    id: str
    image_id: str
    path: Path
    width: int
    height: int
    dpi: int
    angle: float
    was_cut: bool
    split_polygon: Polygon
    stored_outline: Polygon
    entry: dict[str, ET.Element]

    @property
    def whole(self) -> Polygon:
        """The uncut image's corners."""
        w, h = float(self.width), float(self.height)
        return [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]


def child(element: ET.Element, path: str) -> ET.Element:
    """Return the one element at `path` below `element`, raising if absent."""
    found = element.find(path)
    if found is None:
        msg = (
            f"the project has no <{path}> under <{element.tag}>: not a project saved "
            "after Select Content?"
        )
        raise BoxError(msg)
    return found


def points(element: ET.Element) -> Polygon:
    """Return the x, y of each child of `element`."""
    return [(float(p.get("x", "nan")), float(p.get("y", "nan"))) for p in element]


def cut_polygon(pages: ET.Element, height: float) -> Polygon:
    """Return the region between a single-cut layout's two cutter lines."""
    cuts = []
    for tag in ("cutter1", "cutter2"):
        (x1, y1), (x2, y2) = points(child(pages, tag))
        slope = (x2 - x1) / (y2 - y1)
        cuts.append((x1 + slope * (0.0 - y1), x1 + slope * (height - y1)))
    (left_top, left_bottom), (right_top, right_bottom) = sorted(cuts)
    return [
        (left_top, 0.0),
        (right_top, 0.0),
        (right_bottom, height),
        (left_bottom, height),
    ]


def rotated(polygon: Polygon, angle: float) -> tuple[Polygon, tuple[float, float]]:
    """Map a page polygon into the coordinates ScanTailor stores a box in.

    Those are the image's pixels turned by the deskew angle, then moved so
    the turned polygon's bounding box starts at 0, 0. Returns the polygon
    there and the corner that was moved to 0, 0.
    """
    a = math.radians(angle)
    c, s = math.cos(a), math.sin(a)
    turned = [(x * c - y * s, x * s + y * c) for x, y in polygon]
    min_x, min_y = min(p[0] for p in turned), min(p[1] for p in turned)
    return [(x - min_x, y - min_y) for x, y in turned], (min_x, min_y)


def step_pages(root: ET.Element, step: str) -> dict[str, ET.Element]:
    """Return one step's settings for each page, by page id.

    Only the step's own <page> children: a step also keeps image settings
    under <page> elements one level down, with the same ids.
    """
    pages = child(root, f"filters/{step}").findall("page")
    return {p.get("id", ""): p for p in pages}


def load_pages(root: ET.Element) -> list[Page]:
    """Read every page of the project, refusing what this script cannot map."""
    dirs = {d.get("id"): d.get("path", "") for d in child(root, "directories")}
    files = {
        f.get("id"): Path(dirs[f.get("dirId")]) / f.get("name", "")
        for f in child(root, "files")
    }
    images = {i.get("id", ""): i for i in child(root, "images")}
    split = {i.get("id", ""): i for i in child(root, "filters/page-split")}
    steps = {"page-split": split, **{step: step_pages(root, step) for step in STEPS}}
    pages = []
    for number, el in enumerate(child(root, "pages"), start=1):
        page_id, image_id = el.get("id", ""), el.get("imageId", "")
        if el.get("subPage") != "single":
            msg = (
                f"page {number} is the {el.get('subPage')} half of a two-page spread, "
                "which this script does not map; split the scans into single pages "
                "first"
            )
            raise BoxError(msg)
        entry = {}
        for step, by_id in steps.items():
            found = by_id.get(image_id if step == "page-split" else page_id)
            if found is None:
                msg = (
                    f"page {number} has no entry in <{step}>: not a project "
                    "ScanTailor Advanced saved after Select Content on every page?"
                )
                raise BoxError(msg)
            entry[step] = found
        image = images[image_id]
        size = child(image, "size")
        dpi = int(child(image, "dpi").get("horizontal", "0"))
        if child(image, "dpi").get("vertical") != str(dpi):
            msg = (
                f"page {number} is {dpi} dpi across and "
                f"{child(image, 'dpi').get('vertical')} down; unequal resolutions "
                "are not handled (resample the scan to one)"
            )
            raise BoxError(msg)
        if dpi < MIN_DPI:
            msg = (
                f"page {number} is {dpi} dpi; under {MIN_DPI} is not handled (set the "
                "true dpi in ScanTailor's Fix DPI dialog)"
            )
            raise BoxError(msg)
        split_params = child(entry["page-split"], "params")
        if float(child(split_params, "dependencies/rotation").get("degrees", "0")):
            msg = (
                f"page {number} was turned at Fix Orientation, which this script does "
                "not map; turn the image files instead"
            )
            raise BoxError(msg)
        layout = child(split_params, "pages")
        kind = layout.get("type")
        width, height = int(size.get("width", "0")), int(size.get("height", "0"))
        page = Page(
            number=number,
            id=page_id,
            image_id=image_id,
            path=files[image.get("fileId")],
            width=width,
            height=height,
            dpi=dpi,
            angle=float(child(entry["deskew"], "params").get("angle", "nan")),
            was_cut=kind == "single-cut",
            split_polygon=[],
            stored_outline=points(
                child(
                    entry["select-content"],
                    "params/dependencies/rotated-page-outline",
                ),
            )[:4],
            entry=entry,
        )
        if kind == "single-cut":
            page.split_polygon = cut_polygon(layout, float(height))
        elif kind == "single-uncut":
            page.split_polygon = page.whole
        else:
            msg = (
                f"page {number} has the split layout {kind!r}, which this script does "
                "not map"
            )
            raise BoxError(msg)
        pages.append(page)
    return pages


def deskewed_gray(page: Page) -> Image.Image:
    """Return the whole page in the coordinates its content box is stored in.

    Before that, the mapping is proved on this page: the page outline worked
    out here has to match the one ScanTailor stored.
    """
    mine, _ = rotated(page.split_polygon, page.angle)
    error = max(
        min(max(abs(px - qx), abs(py - qy)) for qx, qy in page.stored_outline)
        for px, py in mine
    )
    if error > OUTLINE_SLACK_PX:
        msg = (
            f"page {page.number}: the page outline worked out here is {error:.1f} px "
            "from the one stored in the project, so the coordinate mapping is wrong "
            "for this page"
        )
        raise BoxError(msg)
    gray = Image.open(page.path).convert("L")
    if gray.size != (page.width, page.height):
        msg = (
            f"{page.path} is {gray.size}, the project says "
            f"{(page.width, page.height)}: the image changed since the project was "
            "saved"
        )
        raise BoxError(msg)
    outline, (min_x, min_y) = rotated(page.whole, page.angle)
    size = (
        math.ceil(max(p[0] for p in outline)),
        math.ceil(max(p[1] for p in outline)),
    )
    if page.angle == 0:
        return gray
    a = math.radians(page.angle)
    c, s = math.cos(a), math.sin(a)
    # PIL wants output -> input: the turn undone after the move is.
    inverse = (c, s, c * min_x + s * min_y, -s, c, -s * min_x + c * min_y)
    return gray.transform(
        size,
        Image.Transform.AFFINE,
        inverse,
        resample=Image.Resampling.BICUBIC,
        fillcolor=255,
    )


def find_regions(
    gray: Image.Image,
    page: Page,
    join: tuple[int, int],
) -> tuple[list[dict], int]:
    """Return the page's regions of ink, numbered in reading order, and the specks.

    Ink is counted on a 100 dpi grid; cells within `join` of each other make
    one region. A speck (a few pixels in a few cells) is dropped and counted.
    """
    jpeg = page.path.suffix.lower() in {".jpg", ".jpeg"}
    ink = np.asarray(gray) < (INK_BELOW_JPEG if jpeg else INK_BELOW)
    f = page.dpi // 100
    rows, cols = (ink.shape[0] + f - 1) // f, (ink.shape[1] + f - 1) // f
    padded = np.zeros((rows * f, cols * f), dtype=bool)
    padded[: ink.shape[0], : ink.shape[1]] = ink
    counts = padded.reshape(rows, f, cols, f).sum(axis=(1, 3))
    cells = counts > 0
    reach = np.ones((2 * join[1] + 1, 2 * join[0] + 1), dtype=bool)
    labels, n = ndimage.label(ndimage.binary_dilation(cells, structure=reach))
    labels = np.where(cells, labels, 0)
    regions, specks = [], 0
    for label, where in enumerate(ndimage.find_objects(labels, max_label=n), 1):
        if where is None:
            continue
        ink_px = int(counts[where][labels[where] == label].sum())
        y0, y1, x0, x1 = where[0].start, where[0].stop, where[1].start, where[1].stop
        if ink_px <= SPECK_MAX_INK_PX and max(y1 - y0, x1 - x0) <= SPECK_MAX_CELLS:
            specks += 1
            continue
        regions.append(
            {
                "box": [
                    x0 * f,
                    y0 * f,
                    min(x1 * f, ink.shape[1]),
                    min(y1 * f, ink.shape[0]),
                ],
                "ink_px": ink_px,
                "touches_edge": bool(x0 == 0 or y0 == 0 or x1 == cols or y1 == rows),
            },
        )
    band = page.dpi // 2
    regions.sort(key=lambda r: (r["box"][1] // band, r["box"][0]))
    for number, region in enumerate(regions, start=1):
        region["id"] = number
    return regions, specks


def shrunk(gray: Image.Image, scale: float) -> Image.Image:
    """Return the page scaled down, a hairline kept dark enough to see."""
    size = (round(gray.width * scale), round(gray.height * scale))
    small = gray.resize(size, Image.Resampling.BOX)
    faded = 250
    return small.point(lambda v: 255 if v > faded else int(v * 0.6)).convert("RGB")


def draw_preview(gray: Image.Image, regions: list[dict], target: Path) -> None:
    """Write the page with a numbered box around each region."""
    scale = PREVIEW_LONG_SIDE / max(gray.size)
    image = shrunk(gray, scale)
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=20)
    for region in regions:
        colour = COLOURS[(region["id"] - 1) % len(COLOURS)]
        x0, y0, x1, y1 = (v * scale for v in region["box"])
        draw.rectangle([x0 - 3, y0 - 3, x1 + 3, y1 + 3], outline=colour, width=2)
        text = str(region["id"])
        text_w, text_h = draw.textbbox((0, 0), text, font=font)[2:]
        tag_x = min(max(x0 - 3, 0), image.width - text_w - 6)
        tag_y = y0 - text_h - 9 if y0 - text_h - 9 >= 0 else y1 + 4
        draw.rectangle(
            [tag_x, tag_y, tag_x + text_w + 6, tag_y + text_h + 6],
            fill=colour,
        )
        draw.text((tag_x + 3, tag_y + 1), text, fill="white", font=font)
    partial = target.with_suffix(".partial.png")
    image.save(partial)
    partial.rename(target)


def read_jsonl(path: Path) -> list[dict]:
    """Return the file's records, none if it is not there yet."""
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    return [json.loads(line) for line in lines if line.strip()]


def prepared(page: Page, previews: Path, join: tuple[int, int]) -> tuple[dict, int]:
    """Find one page's regions and draw them; return its record and speck count."""
    gray = deskewed_gray(page)
    regions, specks = find_regions(gray, page, join)
    draw_preview(gray, regions, previews / f"page-{page.number:03d}.png")
    record = {
        "page": page.number,
        "id": page.id,
        "file": page.path.name,
        "dpi": page.dpi,
        "size": list(gray.size),
        "regions": regions,
    }
    return record, specks


def prepare(
    pages: list[Page],
    run: Path,
    log: Log,
    *,
    suffix: str,
    wanted: set[int],
) -> None:
    """Find and draw the regions of each wanted page not yet prepared."""
    previews = run / f"previews{suffix}"
    previews.mkdir(exist_ok=True)
    target = run / f"regions{suffix}.jsonl"
    done = {r["page"] for r in read_jsonl(target)}
    todo = [p for p in pages if p.number in wanted and p.number not in done]
    join = JOIN_FINE if suffix else JOIN
    with (
        target.open("a", buffering=1, encoding="utf-8") as f,
        ThreadPoolExecutor() as pool,
    ):
        results = pool.map(lambda page: prepared(page, previews, join), todo)
        for page, (record, specks) in zip(todo, results, strict=True):
            f.write(json.dumps(record) + "\n")
            log.note(
                f"prepare{suffix} page {page.number:03d} {page.path.name} "
                f"regions={len(record['regions'])} specks={specks} "
                f"angle={page.angle} was_cut={page.was_cut}",
            )


def region_table(record: dict) -> str:
    """Return the page's regions as the table the prompt carries."""
    mm = MM_PER_INCH / record["dpi"]
    rows = [
        "| region | left | top | width | height | touches scan edge |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for region in record["regions"]:
        x0, y0, x1, y1 = region["box"]
        edge = "yes" if region["touches_edge"] else "no"
        rows.append(
            f"| {region['id']} | {x0 * mm:.0f} | {y0 * mm:.0f} "
            f"| {(x1 - x0) * mm:.0f} | {(y1 - y0) * mm:.0f} | {edge} |",
        )
    return "\n".join(rows)


def verdict_problems(verdict: dict, record: dict) -> str:
    """Say what is wrong with a verdict for this page's regions, "" if nothing."""
    ids = {r["id"] for r in record["regions"]}
    problems = []
    for key in ("junk", "mixed", "unsure"):
        unknown = sorted(set(verdict[key]) - ids)
        if unknown:
            problems.append(f"{key} names regions {unknown} that do not exist")
    if set(verdict["junk"]) & (set(verdict["mixed"]) | set(verdict["unsure"])):
        problems.append("a region is listed as junk and as mixed or unsure")
    return "; ".join(problems)


@dataclass
class Judging:
    """What one pass of judging runs with."""

    run: Path
    log: Log
    suffix: str
    model: str
    effort: str


def ask(judging: Judging, record: dict) -> tuple[dict | None, float, str]:
    """Judge one page: its verdict (None if no attempt held), cost, last failure."""
    number = record["page"]
    mm = MM_PER_INCH / record["dpi"]
    prompt = PROMPT.format(
        image=f"previews{judging.suffix}/page-{number:03d}.png",
        page_w=round(record["size"][0] * mm),
        page_h=round(record["size"][1] * mm),
        regions=region_table(record),
    )
    # Only the Read tool, and none of the user's own hooks, skills or MCP
    # servers: the call judges one image and nothing else.
    command = [
        "claude", "-p", prompt,
        "--model", judging.model, "--effort", judging.effort,
        "--output-format", "json", "--json-schema", json.dumps(SCHEMA),
        "--tools", "Read", "--allowedTools", "Read",
        "--no-session-persistence", "--strict-mcp-config",
        "--disable-slash-commands", "--setting-sources", "project",
        "--system-prompt", SYSTEM,
    ]  # fmt: skip
    name = f"judge{judging.suffix} page {number:03d}"
    cost, why = 0.0, ""
    for attempt in range(1, ATTEMPTS + 1):
        start = time.monotonic()
        r = subprocess.run(  # noqa: S603 - our own arguments
            command,
            cwd=judging.run,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            check=False,
        )
        try:
            reply = json.loads(r.stdout)
        except json.JSONDecodeError:
            why = f"exit {r.returncode}, not JSON: {(r.stdout or r.stderr)[:200]!r}"
            judging.log.note(f"{name} attempt {attempt} FAILED {why}")
            continue
        cost += reply.get("total_cost_usd") or 0.0
        verdict = reply.get("structured_output")
        answered_by = sorted(reply.get("modelUsage") or {})
        if r.returncode != 0 or reply.get("is_error") or not isinstance(verdict, dict):
            said = str(reply.get("result"))[:200]
            why = f"exit {r.returncode}, {reply.get('subtype')}: {said!r}"
        elif judging.model not in answered_by:
            why = f"answered by {answered_by}, not {judging.model}"
        else:
            why = verdict_problems(verdict, record)
        if why:
            judging.log.note(f"{name} attempt {attempt} FAILED {why}")
            continue
        calls = judging.run / f"calls{judging.suffix}"
        partial = calls / f"page-{number:03d}.json.partial"
        partial.write_text(json.dumps(reply), encoding="utf-8")
        partial.rename(calls / f"page-{number:03d}.json")
        judging.log.note(
            f"{name} ok {time.monotonic() - start:.0f}s ${cost:.4f} "
            f"attempts={attempt} junk={len(verdict['junk'])} "
            f"mixed={len(verdict['mixed'])} unsure={len(verdict['unsure'])}",
        )
        return {"page": number, **verdict}, cost, ""
    return None, cost, why


def judge(judging: Judging, wanted: set[int], jobs: int) -> None:
    """Judge each wanted page not yet judged, `jobs` calls at a time."""
    suffix = judging.suffix
    records = read_jsonl(judging.run / f"regions{suffix}.jsonl")
    (judging.run / f"calls{suffix}").mkdir(exist_ok=True)
    target = judging.run / f"verdicts{suffix}.jsonl"
    done = {v["page"] for v in read_jsonl(target)}
    todo = [r for r in records if r["page"] in wanted and r["page"] not in done]
    name = f"judge{suffix}"
    judging.log.note(
        f"{name} start: {len(todo)} pages to do, {len(done)} already done, "
        f"{jobs} at a time, {judging.model} effort {judging.effort}, "
        f"about ${len(todo) * COST_PER_PAGE_USD:.2f}",
    )
    total, failed, start = 0.0, {}, time.monotonic()
    with (
        target.open("a", buffering=1, encoding="utf-8") as f,
        ThreadPoolExecutor(jobs) as pool,
    ):
        futures = {}
        for record in todo:
            if record["regions"]:
                futures[pool.submit(ask, judging, record)] = record["page"]
                continue
            blank = {"junk": [], "mixed": [], "unsure": [], "note": "blank, no call"}
            f.write(json.dumps({"page": record["page"], **blank}) + "\n")
            judging.log.note(f"{name} page {record['page']:03d} blank, no call")
        for count, future in enumerate(as_completed(futures), start=1):
            verdict, cost, why = future.result()
            total += cost
            if verdict is None:
                failed[futures[future]] = why
            else:
                f.write(json.dumps(verdict) + "\n")
            if count % 25 == 0:
                judging.log.note(
                    f"{name} progress {count}/{len(futures)} ${total:.2f} "
                    f"{time.monotonic() - start:.0f}s",
                )
    judging.log.note(
        f"{name} end: {len(futures) - len(failed)} judged, {len(failed)} failed, "
        f"${total:.2f}, {time.monotonic() - start:.0f}s",
    )
    if failed:
        msg = (
            f"no valid verdict after {ATTEMPTS} attempts for pages {failed}; fix the "
            f"cause and run again with --run-dir {judging.run} (finished pages are "
            "kept)"
        )
        raise BoxError(msg)


def verdicts_in_force(run: Path, numbers: list[int]) -> dict[int, dict]:
    """Return each page's verdict with the regions it speaks of.

    An override wins, then the fine pass, then the first. Every page needs
    one, and an override is checked as a model's verdict is.
    """
    regions = {
        name: {r["page"]: r for r in read_jsonl(run / f"regions{suffix}.jsonl")}
        for name, suffix in PASSES.items()
    }
    chosen: dict[int, dict] = {}
    for name, suffix in PASSES.items():
        for verdict in read_jsonl(run / f"verdicts{suffix}.jsonl"):
            record = regions[name][verdict["page"]]
            chosen[verdict["page"]] = {**verdict, "source": name, "record": record}
    for line, override in enumerate(read_jsonl(run / "overrides.jsonl"), start=1):
        where = f"{run / 'overrides.jsonl'} record {line}"
        if override.get("pass") not in regions or "junk" not in override:
            msg = f'{where}: needs "page", "pass" ("first" or "fine") and "junk"'
            raise BoxError(msg)
        record = regions[override["pass"]].get(override["page"])
        if record is None:
            msg = f"{where}: page {override['page']} has no {override['pass']} pass"
            raise BoxError(msg)
        verdict = {
            "page": override["page"],
            "junk": override["junk"],
            "mixed": [],
            "unsure": [],
            "note": override.get("note", "by hand"),
        }
        problem = verdict_problems(verdict, record)
        if problem:
            msg = f"{where}: {problem}"
            raise BoxError(msg)
        source = f"override ({override['pass']})"
        chosen[override["page"]] = {**verdict, "source": source, "record": record}
    missing = sorted(set(numbers) - set(chosen))
    if missing:
        msg = (
            f"no verdict for pages {missing}; run again with --run-dir {run} and no "
            "--pages"
        )
        raise BoxError(msg)
    return chosen


def number_text(value: float) -> str:
    """Write a number as ScanTailor does: no decimal point on a whole one."""
    return str(int(value)) if float(value) == int(value) else repr(float(value))


def set_points(element: ET.Element, polygon: Polygon) -> None:
    """Replace the element's points by the polygon's, closed, indented alike."""
    indent = element.text if element.text and not element.text.strip() else "\n"
    for old in list(element):
        element.remove(old)
    element.text = indent
    closed = [*polygon, polygon[0]]
    for i, (x, y) in enumerate(closed):
        point = ET.SubElement(element, "point", x=number_text(x), y=number_text(y))
        point.tail = indent if i < len(closed) - 1 else indent[:-2]


def uncut(page: Page) -> None:
    """Make a page ScanTailor cut at Split Pages a whole page in every step."""
    image = page.entry["page-split"]
    image.set("layoutType", "single-uncut")
    params = child(image, "params")
    params.set("mode", "manual")
    layout = child(params, "pages")
    layout.set("type", "single-uncut")
    for tag in ("cutter1", "cutter2"):
        layout.remove(child(layout, tag))
    child(layout, "outline").tail = (layout.text or "\n")[:-2]
    child(params, "dependencies/layoutType").text = "single-uncut"

    deskew = child(page.entry["deskew"], "params")
    deskew.set("mode", "manual")
    set_points(child(deskew, "dependencies/page-outline"), page.whole)

    outline, _ = rotated(page.whole, page.angle)
    select = child(page.entry["select-content"], "params")
    set_points(child(select, "dependencies/rotated-page-outline"), outline)
    rect = child(select, "page-rect")
    rect.set("x", "0")
    rect.set("y", "0")
    rect.set("width", number_text(max(p[0] for p in outline)))
    rect.set("height", number_text(max(p[1] for p in outline)))


def stored_box(page: Page) -> Box | None:
    """Return ScanTailor's own box as x0, y0, x1, y1 on the whole page, if any."""
    rect = child(page.entry["select-content"], "params/content-rect")
    x, y, w, h = (float(rect.get(k, "nan")) for k in ("x", "y", "width", "height"))
    if w <= 0 or h <= 0:
        return None
    # A cut page's box is stored relative to the cut; move it to the whole page.
    _, cut_corner = rotated(page.split_polygon, page.angle)
    _, whole_corner = rotated(page.whole, page.angle)
    dx, dy = cut_corner[0] - whole_corner[0], cut_corner[1] - whole_corner[1]
    return [x + dx, y + dy, x + w + dx, y + h + dy]


def write_box(page: Page, box: Box | None) -> None:
    """Store the box (None: no content) as the page's content box."""
    params = child(page.entry["select-content"], "params")
    x0, y0, x1, y1 = box or [0.0, 0.0, 0.0, 0.0]
    rect = child(params, "content-rect")
    for key, value in (("x", x0), ("y", y0), ("width", x1 - x0), ("height", y1 - y0)):
        rect.set(key, number_text(value))
    size = params.find("content-size-mm")
    if box is None:
        if size is not None:
            params.remove(size)
        return
    if size is None:
        page_rect = child(params, "page-rect")
        size = ET.Element("content-size-mm")
        size.tail = page_rect.tail
        params.insert(list(params).index(page_rect) + 1, size)
    mm = MM_PER_INCH / page.dpi
    size.set("width", number_text((x1 - x0) * mm))
    size.set("height", number_text((y1 - y0) * mm))


def geometry_only(page: Page) -> None:
    """Set the page's Margins and Output steps to change nothing but geometry."""
    layout = child(page.entry["page-layout"], "params")
    layout.set("autoMargins", "0")
    for side in ("top", "right", "bottom", "left"):
        child(layout, "hardMarginsMM").set(side, "0")
    alignment = child(layout, "alignment")
    alignment.set("null", "0")
    alignment.set("hor", "original")
    alignment.set("vert", "original")
    output = child(page.entry["output"], "params")
    output.set("despeckleLevel", "0")
    child(output, "dewarping-options").set("mode", "off")
    for axis in ("horizontal", "vertical"):
        child(output, "dpi").set(axis, str(page.dpi))
    child(output, "splitting").set("splitOutput", "0")
    colours = child(output, "color-params")
    colours.set("colorMode", "colorOrGray")
    as_scanned = child(colours, "color-or-grayscale")
    # Off, the junk outside the box would show in the room size matching adds.
    as_scanned.set("fillMargins", "1")
    as_scanned.set("normalizeIlluminationColor", "0")
    child(as_scanned, "posterization-options").set("enabled", "0")


def revise(pages: list[Page], verdicts: dict[int, dict]) -> list[dict]:
    """Set every page's box in the project tree; return a report row a page."""
    rows = []
    for page in pages:
        verdict = verdicts[page.number]
        record = verdict["record"]
        if record["id"] != page.id:
            msg = (
                f"page {page.number} is id {page.id} in the project but "
                f"{record['id']} in the run's folder: the run belongs to another "
                "project"
            )
            raise BoxError(msg)
        old = stored_box(page)
        junk = set(verdict["junk"])
        kept = [r["box"] for r in record["regions"] if r["id"] not in junk]
        new = (
            [
                min(b[0] for b in kept),
                min(b[1] for b in kept),
                max(b[2] for b in kept),
                max(b[3] for b in kept),
            ]
            if kept
            else None
        )
        mm = MM_PER_INCH / page.dpi
        moves = [None, None, None, None]
        if old and new:
            moves = [(n - o) * mm for n, o in zip(new, old, strict=True)]
            changed = max(abs(m) for m in moves) > TOLERANCE_MM
        else:
            changed = (old is None) != (new is None)
        if page.was_cut:
            uncut(page)
        if changed or page.was_cut:
            write_box(page, new if changed else old)
        params = child(page.entry["select-content"], "params")
        params.set("contentDetectionMode", "manual")
        child(params, "dependencies/params").set("contentDetectionMode", "manual")
        geometry_only(page)
        rows.append(
            {
                "page": page.number,
                "file": page.path.name,
                "action": ("uncut+" if page.was_cut else "")
                + ("revised" if changed else "kept"),
                "left_mm": moves[0],
                "top_mm": moves[1],
                "right_mm": moves[2],
                "bottom_mm": moves[3],
                "scantailor_box": old,
                "revised_box": new,
                "regions": len(record["regions"]),
                "junk": sorted(junk),
                "mixed": verdict["mixed"],
                "unsure": verdict["unsure"],
                "note": verdict["note"],
                "source": verdict["source"],
            },
        )
    return rows


def write_report(rows: list[dict], run: Path) -> None:
    """Write the rows as report.tsv."""
    with (run / "report.tsv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), delimiter="\t")
        writer.writeheader()
        for row in rows:
            text = dict(row)
            for key in ("left_mm", "top_mm", "right_mm", "bottom_mm"):
                text[key] = "" if row[key] is None else f"{row[key]:+.1f}"
            for key in ("scantailor_box", "revised_box"):
                box = row[key]
                text[key] = "" if box is None else " ".join(str(round(v)) for v in box)
            for key in ("junk", "mixed", "unsure"):
                text[key] = " ".join(map(str, row[key]))
            writer.writerow(text)


def write_project(tree: "ET.ElementTree[ET.Element]", target: Path) -> None:
    """Write the project, whole or not at all, and prove it parses."""
    partial = target.with_name(target.name + ".partial")
    tree.write(partial, encoding="utf-8", xml_declaration=False)
    with partial.open("a", encoding="utf-8") as f:
        f.write("\n")
    ET.parse(partial)  # noqa: S314 - the file this script just wrote
    partial.rename(target)


def sheets(cells: list[Image.Image], folder: Path, per_row: int, rows: int) -> int:
    """Paste the cells onto sheets of per_row by rows; return how many sheets."""
    folder.mkdir(exist_ok=True)
    for old in folder.glob("sheet-*.png"):
        old.unlink()
    per_sheet = per_row * rows
    for first in range(0, len(cells), per_sheet):
        batch = cells[first : first + per_sheet]
        w = max(c.width for c in batch) + 10
        h = max(c.height for c in batch) + 10
        sheet = Image.new("RGB", (w * per_row, h * rows), "#808080")
        for i, cell in enumerate(batch):
            sheet.paste(cell, ((i % per_row) * w + 5, (i // per_row) * h + 5))
        sheet.save(folder / f"sheet-{first // per_sheet + 1:02d}.png")
    return -(-len(cells) // per_sheet)


def compare_cells(pages: list[Page], rows: list[dict]) -> list[Image.Image]:
    """Draw each page whose box changed: ScanTailor's in red, the new in green."""
    height = 700
    font = ImageFont.load_default(size=26)
    cells = []
    for page, row in zip(pages, rows, strict=True):
        if row["action"] == "kept":
            continue
        gray = deskewed_gray(page)
        scale = height / gray.height
        image = shrunk(gray, scale)
        draw = ImageDraw.Draw(image)
        for key, colour, pad in (
            ("scantailor_box", "#e00000", 0),
            ("revised_box", "#00a030", 3),
        ):
            if row[key]:
                x0, y0, x1, y1 = (v * scale for v in row[key])
                box = [x0 - pad, y0 - pad, x1 + pad, y1 + pad]
                draw.rectangle(box, outline=colour, width=2)
        draw.rectangle([0, 0, 150, 34], fill="black")
        draw.text((6, 2), f"p {page.number}", fill="white", font=font)
        cells.append(image)
    return cells


def could_cost_content(region: dict, row: dict, record: dict) -> bool:
    """Say whether a region is junk outside the kept box and off the scan edge."""
    x0, y0, x1, y1 = region["box"]
    width, height = record["size"]
    near = EDGE_MM / MM_PER_INCH * record["dpi"]
    kept = row["revised_box"]
    inside = kept and (
        x0 >= kept[0] and y0 >= kept[1] and x1 <= kept[2] and y1 <= kept[3]
    )
    at_edge = x1 < near or y1 < near or x0 > width - near or y0 > height - near
    return region["id"] in row["junk"] and not inside and not at_edge


def junk_cells(
    pages: list[Page],
    rows: list[dict],
    verdicts: dict[int, dict],
) -> list[Image.Image]:
    """Crop each junk region that could have cost content.

    That is one outside the kept box and more than EDGE_MM from every scan
    edge: where a page number or a footnote mark judged junk would be.
    """
    cell_px = 260
    font = ImageFont.load_default(size=18)
    cells = []
    for page, row in zip(pages, rows, strict=True):
        record = verdicts[page.number]["record"]
        todo = [r for r in record["regions"] if could_cost_content(r, row, record)]
        if not todo:
            continue
        gray = deskewed_gray(page)
        for region in todo:
            x0, y0, x1, y1 = region["box"]
            pad = max(60, max(x1 - x0, y1 - y0) // 3)
            crop = gray.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad))
            scale = (cell_px - 30) / max(crop.size)
            size = (
                max(1, round(crop.width * scale)),
                max(1, round(crop.height * scale)),
            )
            crop = crop.resize(size, Image.Resampling.BOX).convert("RGB")
            edge = pad * scale - 2
            ImageDraw.Draw(crop).rectangle(
                [edge, edge, crop.width - edge, crop.height - edge],
                outline="#e00000",
            )
            cell = Image.new("RGB", (cell_px, cell_px), "white")
            cell.paste(crop, (0, 26))
            draw = ImageDraw.Draw(cell)
            draw.rectangle([0, 0, cell_px, 24], fill="black")
            label = f"p{page.number} r{region['id']} {x1 - x0}x{y1 - y0}"
            draw.text((4, 2), label, fill="white", font=font)
            cells.append(cell)
    return cells


def summarise(rows: list[dict], run: Path, target: Path, log: Log) -> None:
    """Log what changed, what is left for a person, and where to look."""
    actions = [r["action"] for r in rows]
    revised = sum(a.endswith("revised") for a in actions)
    whole_again = sum(a.startswith("uncut") for a in actions)
    costs = [
        json.loads(p.read_text(encoding="utf-8"))["total_cost_usd"]
        for p in run.glob("calls*/page-*.json")
    ]
    log.note(
        f"pages {len(rows)}: box revised {revised}, kept {actions.count('kept')}, "
        f"taken whole again {whole_again}; {len(costs)} calls, ${sum(costs):.2f}",
    )
    left = {
        r["page"]: r["mixed"] + r["unsure"] for r in rows if r["mixed"] + r["unsure"]
    }
    if left:
        log.note(f"regions still mixed or unsure, kept as content: {left}")
    log.note(f"revised project, Margins and Output set to geometry only: {target}")
    log.note(f"check by eye: {run / 'compare'} and {run / 'junk'}; rows: report.tsv")


def run_dir(project: Path, given: Path | None) -> Path:
    """Return the run's folder, made beside the project unless one is given."""
    if given is not None:
        if not given.is_dir():
            msg = f"--run-dir {given} is not a folder"
            raise BoxError(msg)
        return given.resolve()
    stamp = f"{datetime.now(UTC):%Y%m%d_%H%M%S}"
    run = project.parent / ".logs" / f"{stamp}_content_boxes"
    run.mkdir(parents=True)
    return run


def arguments(argv: list[str]) -> argparse.Namespace:
    """Parse the command line."""
    p = argparse.ArgumentParser(
        prog="scantailor_boxes.py",
        description=(__doc__ or "").split("\n")[0],
    )
    p.add_argument("project", type=Path, help="saved after Select Content")
    p.add_argument("--out", type=Path, help="default: <project>_revised.ScanTailor")
    p.add_argument("--run-dir", type=Path, help="carry on the run in this folder")
    p.add_argument(
        "--pages",
        type=int,
        nargs="+",
        help="a pilot: prepare and judge only these, then stop",
    )
    p.add_argument(
        "--stop-after",
        choices=["prepare"],
        help="stop there, before any call is paid for",
    )
    p.add_argument("--jobs", type=int, default=8, help="calls at a time")
    p.add_argument("--model", default=MODEL, help="a full model id")
    p.add_argument("--effort", default=EFFORT)
    return p.parse_args(argv)


def places(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    """Return the project, the file its revision goes in and the run's folder."""
    project = args.project.resolve()
    default = project.with_name(f"{project.stem}_revised.ScanTailor")
    target = (args.out or default).resolve()
    if target == project:
        msg = "--out is the project itself; the revision goes in a file of its own"
        raise BoxError(msg)
    return project, target, run_dir(project, args.run_dir)


def work(
    args: argparse.Namespace,
    project: Path,
    target: Path,
    run: Path,
    log: Log,
) -> None:
    """Run every stage not yet done, up to where the arguments say to stop."""
    tree = ET.parse(project)  # noqa: S314 - the user's own project file
    root = tree.getroot()
    pages = load_pages(root)
    numbers = [page.number for page in pages]
    wanted = set(args.pages or numbers)
    if wanted - set(numbers):
        msg = (
            f"--pages names {sorted(wanted - set(numbers))}; the project has "
            f"pages 1 to {len(pages)}"
        )
        raise BoxError(msg)
    prepare(pages, run, log, suffix=PASSES["first"], wanted=wanted)
    if args.stop_after == "prepare":
        return
    first = Judging(run, log, PASSES["first"], args.model, args.effort)
    judge(first, wanted, args.jobs)
    if args.pages:
        log.note(f"pilot done: {run / 'verdicts.jsonl'}; carry on with --run-dir")
        return
    mixed = {v["page"] for v in read_jsonl(run / "verdicts.jsonl") if v["mixed"]}
    mixed |= {r["page"] for r in read_jsonl(run / "regions-fine.jsonl")}
    if mixed:
        prepare(pages, run, log, suffix=PASSES["fine"], wanted=mixed)
        fine = Judging(run, log, PASSES["fine"], args.model, args.effort)
        judge(fine, mixed, args.jobs)
    verdicts = verdicts_in_force(run, numbers)
    rows = revise(pages, verdicts)
    write_project(tree, target)
    write_report(rows, run)
    n = sheets(compare_cells(pages, rows), run / "compare", per_row=4, rows=2)
    log.note(f"compare: {n} sheets")
    n = sheets(junk_cells(pages, rows, verdicts), run / "junk", per_row=8, rows=5)
    log.note(f"junk: {n} sheets")
    summarise(rows, run, target, log)


def main(argv: list[str]) -> int:
    """Revise the project argv names."""
    args = arguments(argv)
    try:
        project, target, run = places(args)
    except BoxError as e:
        sys.stderr.write(f"scantailor_boxes.py: {e}\n")
        return 1
    log = Log(run)
    log.note(f"run folder: {run}")
    try:
        work(args, project, target, run, log)
    except BoxError as e:
        log.note(f"FAILED: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
