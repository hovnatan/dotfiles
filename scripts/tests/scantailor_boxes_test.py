# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=11"]
# ///
"""The book-scan skill's scantailor_boxes.py, end to end on a made-up book.

    scantailor_boxes_test.py <repo> <work dir, with bin/claude the stub> <events.log>

Four 200 dpi pages, each a page number (top right), a block of text and a
shadow in the bottom-left corner, in a project as ScanTailor Advanced saves
one after Select Content:

  page  as ScanTailor left it               expect
  all   Margins 10 and 5 mm, content    no margins, content where it
        centred; Output black and       stood (Original); Output Color /
        white, 600 dpi, despeckled      Grayscale at 200 dpi, undespeckled
  1     box takes in the shadow             box = number + text; the stub
                                            calls its text mixed, so the
                                            fine pass judges it again
  2     box already number + text           kept as it is
  3     cut at Split Pages; box misses the  whole page again (no cutters),
        number                              box = number + text
  4     deskewed by 1 degree                the text lands where the turn
                                            puts it, within 4 px

The stub claude (the .sh's header) answers from the prompt's own table, so
the run pays for nothing and still goes through every call.

  prepare     --stop-after prepare: the regions, no call made
  whole run   5 calls (4 pages, 1 fine), each with the model and the Read
              tool only; every page manual; the source project untouched;
              the report's actions; one compare sheet; the last two steps
              of every page geometry only
  resume      the same run again: no call
  override    page 1's number judged junk by hand moves the box's top; one
              naming a region that does not exist is refused, naming it
  refusals    --out the project itself; a two-page spread
"""

# A test run by its .sh, no license header, as in scripts/tests.
# ruff: noqa: S101, CPY001, D103, S603

import json
import math
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts/lib"))
from event_log import EventLog

REPO, WORK, LOG = (Path(a) for a in sys.argv[1:4])
log = EventLog(LOG.open("a", buffering=1, encoding="utf-8"), sys.stdout).note
SCRIPT = REPO / "home/.agents/skills/book-scan/scantailor_boxes.py"
BOOK = WORK / "book"
CALLS = WORK / "calls.jsonl"
W, H, DPI = 800, 1100, 200
NUMBER = [630, 120, 650, 134]
TEXT = [150, 200, 650, 790]
SHADOW = [0, 1000, 120, 1100]
CUT = (140.0, 700.0)
ANGLE = 1.0
SLACK_PX = 4
MARGIN_SIDES = ("top", "right", "bottom", "left")
GEOMETRY_ONLY = (
    *("0", "0", "0", "0"),
    *("0", "original", "original"),
    *("0", "200", "200", "off", "colorOrGray", "1", "0"),
)
# A page's Output settings as ScanTailor Advanced 1.0.19 saves them untouched.
OUTPUT_AS_SAVED = """\
        <zones/>
        <fill-zones/>
        <params depthPerception="2" despeckleLevel="1" blackOnWhite="1">
          <picture-shape-options higherSearchSensitivity="0" sensitivity="100"
            pictureShape="free"/>
          <dewarping-options mode="off" postDeskew="1" postDeskewAngle="0"/>
          <dpi horizontal="600" vertical="600"/>
          <color-params colorMode="bw">
            <color-or-grayscale fillOffcut="1" normalizeIlluminationColor="0"
              fillMargins="1" fillingColor="background">
              <posterization-options forceBlackAndWhite="1" level="4" enabled="0"
                normalizationEnabled="0"/>
            </color-or-grayscale>
            <bw morphologicalSmoothing="1" binarizationMethod="otsu" wolfCoef="0.3"
              wolfLowerBound="1" wolfUpperBound="254" windowSize="200"
              sauvolaCoef="0.34" savitzkyGolaySmoothing="1"
              normalizeIlluminationBW="1" thresholdAdj="0">
              <color-segmenter-options redThresholdAdjustment="0" noiseReduction="7"
                enabled="0" greenThresholdAdjustment="0" blueThresholdAdjustment="0"/>
            </bw>
          </color-params>
          <splitting splittingMode="bw" splitOutput="0" originalBackground="0"/>
        </params>
        <processing-params blackOnWhiteSetManually="0" autoZonesFound="0"/>
"""


def draw_page(path: Path) -> None:
    image = Image.new("L", (W, H), 255)
    draw = ImageDraw.Draw(image)
    x0, y0, x1, y1 = NUMBER
    draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=0)
    x0, y0, x1, y1 = TEXT
    for top in range(y0, y1, 20):
        draw.rectangle([x0, top, x1 - 1, top + 9], fill=0)
    x0, y0, x1, y1 = SHADOW
    draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=0)
    image.save(path, dpi=(DPI, DPI))


def turned(polygon: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Map points as ScanTailor does for page 4: turn, then the box to 0, 0."""
    a = math.radians(ANGLE)
    c, s = math.cos(a), math.sin(a)
    corners = [(0.0, 0.0), (W, 0.0), (W, H), (0.0, H)]
    min_x = min(x * c - y * s for x, y in corners)
    min_y = min(x * s + y * c for x, y in corners)
    return [(x * c - y * s - min_x, x * s + y * c - min_y) for x, y in polygon]


def turned_box(box: list[int]) -> list[float]:
    """Return what bounds a box of the image once page 4's turn has moved it."""
    x0, y0, x1, y1 = box
    corners = turned([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    xs, ys = [p[0] for p in corners], [p[1] for p in corners]
    return [min(xs), min(ys), max(xs), max(ys)]


def page_4_box() -> list[float]:
    """Return the box page 4 is saved with: its number and text, turned."""
    number, text = turned_box(NUMBER), turned_box(TEXT)
    return [
        min(number[0], text[0]),
        min(number[1], text[1]),
        max(number[2], text[2]),
        max(number[3], text[3]),
    ]


def outline(polygon: list[tuple[float, float]], indent: str) -> str:
    closed = [*polygon, polygon[0]]
    return "".join(f'{indent}<point x="{x!r}" y="{y!r}"/>\n' for x, y in closed)


def project(sub_page: str = "single") -> str:
    """Return the project: page n is id n0, its image n1, its file n2."""
    whole = [(0.0, 0.0), (float(W), 0.0), (float(W), float(H)), (0.0, float(H))]
    cut_width = CUT[1] - CUT[0]
    cut = [(0.0, 0.0), (cut_width, 0.0), (cut_width, float(H)), (0.0, float(H))]
    cutters = (
        f'            <cutter1>\n              <p1 x="{CUT[0]}" y="{H - 1}"/>\n'
        f'              <p2 x="{CUT[0]}" y="0"/>\n            </cutter1>\n'
        f'            <cutter2>\n              <p1 x="{CUT[1]}" y="{H - 1}"/>\n'
        f'              <p2 x="{CUT[1]}" y="0"/>\n            </cutter2>\n'
    )
    # x0, y0, x1, y1 of the box each page was saved with, in its own coordinates
    boxes = {
        1: [0, NUMBER[1], TEXT[2], SHADOW[3]],
        2: [TEXT[0], NUMBER[1], TEXT[2], TEXT[3]],
        3: [TEXT[0] - CUT[0], TEXT[1], TEXT[2] - CUT[0], TEXT[3]],
        4: page_4_box(),
    }
    files = images = pages = split = deskew = select = layout = output = ""
    for n in (1, 2, 3, 4):
        angle = ANGLE if n == 4 else 0.0  # noqa: PLR2004 - page 4 is the turned one
        is_cut = n == 3  # noqa: PLR2004 - page 3 is the cut one
        stored = cut if is_cut else turned(whole) if angle else whole
        x0, y0, x1, y1 = boxes[n]
        files += f'    <file id="{n}2" dirId="1" name="page-{n:03d}.png"/>\n'
        images += (
            f'    <image id="{n}1" subPages="1" fileImage="0" fileId="{n}2">\n'
            f'      <size width="{W}" height="{H}"/>\n'
            f'      <dpi horizontal="{DPI}" vertical="{DPI}"/>\n    </image>\n'
        )
        pages += f'    <page id="{n}0" imageId="{n}1" subPage="{sub_page}"/>\n'
        split += (
            f'      <image id="{n}1" layoutType="auto-detect">\n'
            '        <params mode="auto">\n'
            f'          <pages type="{"single-cut" if is_cut else "single-uncut"}">\n'
            f"            <outline>\n{outline(whole, ' ' * 14)}            </outline>\n"
            f"{cutters if is_cut else ''}          </pages>\n"
            '          <dependencies>\n            <rotation degrees="0"/>\n'
            f'            <size width="{W}" height="{H}"/>\n'
            "            <layoutType>auto-detect</layoutType>\n"
            "          </dependencies>\n        </params>\n      </image>\n"
        )
        deskew += (
            f'      <page id="{n}0">\n        <params mode="auto" angle="{angle!r}">\n'
            '          <dependencies>\n            <rotation degrees="0"/>\n'
            f"            <page-outline>\n{outline(whole, ' ' * 14)}"
            "            </page-outline>\n          </dependencies>\n"
            "        </params>\n      </page>\n"
        )
        mode = 'pageDetectionMode="disabled" contentDetectionMode="auto"'
        select += (
            f'      <page id="{n}0">\n        <params {mode} fineTuneCorners="0">\n'
            f'          <content-rect width="{x1 - x0}" x="{x0}" y="{y0}" '
            f'height="{y1 - y0}"/>\n'
            f'          <page-rect width="{W}" x="0" y="0" height="{H}"/>\n'
            '          <content-size-mm width="1" height="1"/>\n'
            "          <dependencies>\n            <rotated-page-outline>\n"
            f"{outline(stored, ' ' * 14)}            </rotated-page-outline>\n"
            f'            <params {mode} fineTuneCorners="0"/>\n'
            "          </dependencies>\n        </params>\n      </page>\n"
        )
        layout += (
            f'      <page id="{n}0">\n        <params autoMargins="0">\n'
            '          <hardMarginsMM top="5" right="10" left="10" bottom="5"/>\n'
            '          <pageRect width="0" x="0" y="0" height="0"/>\n'
            '          <contentRect width="0" x="0" y="0" height="0"/>\n'
            '          <contentSizeMM width="-1" height="-1"/>\n'
            '          <alignment null="0" hor="center" vert="center"/>\n'
            "        </params>\n      </page>\n"
        )
        output += f'      <page id="{n}0">\n{OUTPUT_AS_SAVED}      </page>\n'
    return (
        f'<project version="3" layoutDirection="LTR" outputDirectory="{BOOK}/out">\n'
        f'  <directories>\n    <directory id="1" path="{BOOK}"/>\n  </directories>\n'
        f"  <files>\n{files}  </files>\n  <images>\n{images}  </images>\n"
        f"  <pages>\n{pages}  </pages>\n  <filters>\n"
        f"    <page-split>\n{split}    </page-split>\n"
        # A step keeps image settings under <page> one level down as well.
        '    <deskew>\n      <image-settings>\n        <page id="10"/>\n'
        f"      </image-settings>\n{deskew}    </deskew>\n"
        f'    <select-content pageDetectionTolerance="0.1">\n{select}'
        "    </select-content>\n"
        f'    <page-layout showMiddleRect="1">\n{layout}    </page-layout>\n'
        f"    <output>\n{output}    </output>\n  </filters>\n</project>\n"
    )


def boxes_script(*args: str | Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [SCRIPT, *map(str, args)],
        capture_output=True,
        text=True,
        check=False,
    )


def calls() -> list[list[str]]:
    if not CALLS.exists():
        return []
    return [json.loads(line) for line in CALLS.read_text().splitlines()]


def run_folder() -> Path:
    (run,) = (BOOK / ".logs").iterdir()
    return run


def regions(run: Path, page: int, suffix: str = "") -> list[list[int]]:
    lines = (run / f"regions{suffix}.jsonl").read_text().splitlines()
    record = next(r for r in map(json.loads, lines) if r["page"] == page)
    return [r["box"] for r in record["regions"]]


def last_steps(revised: Path) -> set[tuple[str, ...]]:
    """Return the Margins and Output settings found, one tuple a distinct page."""
    root = ET.parse(revised).getroot()  # noqa: S314 - written by the script under test
    found = set()
    for n in (1, 2, 3, 4):
        layout = root.find(f"filters/page-layout/page[@id='{n}0']/params")
        output = root.find(f"filters/output/page[@id='{n}0']/params")
        assert layout is not None, f"page {n} lost its Margins settings"
        assert output is not None, f"page {n} lost its Output settings"
        values = [
            *(layout.find("hardMarginsMM").get(side) for side in MARGIN_SIDES),
            layout.find("alignment").get("null"),
            layout.find("alignment").get("hor"),
            layout.find("alignment").get("vert"),
            output.get("despeckleLevel"),
            output.find("dpi").get("horizontal"),
            output.find("dpi").get("vertical"),
            output.find("dewarping-options").get("mode"),
            output.find("color-params").get("colorMode"),
            output.find("color-params/color-or-grayscale").get("fillMargins"),
            output.find("splitting").get("splitOutput"),
        ]
        found.add(tuple(str(v) for v in values))
    return found


def content_rect(revised: Path, page: int) -> list[float]:
    root = ET.parse(revised).getroot()  # noqa: S314 - written by the script under test
    select = root.find("filters/select-content")
    assert select is not None
    (rect,) = select.findall(f"page[@id='{page}0']/params/content-rect")
    return [float(rect.get(k, "nan")) for k in ("x", "y", "width", "height")]


def run_end_to_end() -> None:  # noqa: PLR0915 - one story, step by step
    BOOK.mkdir()
    for n in (1, 2, 3, 4):
        draw_page(BOOK / f"page-{n:03d}.png")
    source = BOOK / "book.ScanTailor"
    source.write_text(project())
    saved = source.read_bytes()
    revised = BOOK / "book_revised.ScanTailor"

    r = boxes_script(source, "--stop-after", "prepare")
    assert r.returncode == 0, r.stdout + r.stderr
    run = run_folder()
    assert regions(run, 1) == [NUMBER, TEXT, SHADOW], regions(run, 1)
    assert regions(run, 3) == [NUMBER, TEXT, SHADOW], "the cut page is taken whole"
    expect = turned_box(TEXT)
    found = regions(run, 4)[1]
    off = max(abs(a - b) for a, b in zip(found, expect, strict=True))
    assert off <= SLACK_PX, f"page 4 text at {found}, the turn puts it at {expect}"
    assert not calls(), "prepare made a call"
    assert not revised.exists()
    log("PASS prepare: the regions of a plain, a cut and a turned page, no call")

    r = boxes_script(source, "--run-dir", run)
    assert r.returncode == 0, r.stdout + r.stderr
    made = calls()
    assert len(made) == 4 + 1, f"{len(made)} calls: {r.stdout}"
    for argv in made:
        for flag, value in (
            ("--model", "claude-sonnet-5-5"),
            ("--effort", "medium"),
            ("--tools", "Read"),
        ):
            assert argv[argv.index(flag) + 1] == value, argv
    assert len(regions(run, 1, "-fine")) > len(regions(run, 1)), "no finer regions"
    log("PASS whole run: 4 pages and 1 fine page judged, Read the only tool")

    x0, y0, x1, y1 = page_4_box()
    turned_rect = [x0, y0, x1 - x0, y1 - y0]
    box = [TEXT[0], NUMBER[1], TEXT[2] - TEXT[0], TEXT[3] - NUMBER[1]]
    assert content_rect(revised, 1) == box, content_rect(revised, 1)
    assert content_rect(revised, 2) == box, "page 2 was to be kept"
    assert content_rect(revised, 3) == box, content_rect(revised, 3)
    assert content_rect(revised, 4) == turned_rect, "page 4 was to be kept"
    text = revised.read_text()
    assert text.count('contentDetectionMode="manual"') == 2 * 4, "not all manual"
    assert "contentDetectionMode" not in text.replace(
        'contentDetectionMode="manual"',
        "",
    )
    assert "cutter" not in text, "page 3 is still cut"
    assert 'type="single-cut"' not in text, "page 3's layout"
    assert source.read_bytes() == saved, "the source project changed"
    rows = (run / "report.tsv").read_text().splitlines()[1:]
    actions = [row.split("\t")[2] for row in rows]
    assert actions == ["revised", "kept", "uncut+revised", "kept"], actions
    assert rows[0].split("\t")[-1] == "fine", rows[0]
    assert [p.name for p in (run / "compare").iterdir()] == ["sheet-01.png"]
    log("PASS whole run: boxes, every page manual, page 3 whole, source untouched")
    assert last_steps(revised) == {GEOMETRY_ONLY}, last_steps(revised)
    assert last_steps(source) != {GEOMETRY_ONLY}, "the fixture is geometry only already"
    log("PASS whole run: Margins and Output of every page set to geometry only")

    r = boxes_script(source, "--run-dir", run)
    assert r.returncode == 0, r.stdout + r.stderr
    assert len(calls()) == len(made), "a finished run made calls again"
    log("PASS resume: nothing judged twice")

    x0, y0, x1, y1 = TEXT
    overrides = run / "overrides.jsonl"
    overrides.write_text('{"page": 1, "pass": "first", "junk": [1, 3]}\n')
    r = boxes_script(source, "--run-dir", run)
    assert r.returncode == 0, r.stdout + r.stderr
    assert content_rect(revised, 1) == [x0, y0, x1 - x0, y1 - y0], "override not used"
    overrides.write_text('{"page": 1, "pass": "first", "junk": [9]}\n')
    r = boxes_script(source, "--run-dir", run)
    assert r.returncode == 1, "a region that does not exist was accepted"
    assert "junk names regions [9] that do not exist" in r.stdout, r.stdout
    log("PASS override: used over both passes; a wrong one refused by name")

    r = boxes_script(source, "--out", source)
    assert r.returncode == 1, "--out the project itself was accepted"
    assert "the project itself" in r.stderr, r.stderr
    spread = WORK / "spread"
    spread.mkdir()
    (spread / "book.ScanTailor").write_text(project(sub_page="left"))
    r = boxes_script(spread / "book.ScanTailor")
    assert r.returncode == 1, "a two-page spread was accepted"
    assert "two-page spread" in r.stdout, r.stdout
    log("PASS refusals: --out the project itself; a two-page spread")


try:
    run_end_to_end()
except Exception as e:  # noqa: BLE001 - whatever stopped the story is the failure
    log(f"FAIL {type(e).__name__}: {e}")
    log(f"kept work dir: {WORK}")
    sys.exit(1)
shutil.rmtree(WORK)
