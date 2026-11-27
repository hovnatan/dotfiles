#!/usr/bin/env python3
r"""Turn a book's contents, typed by printed page number, into pdftocio's toc.

    toc_pages.py <ocr.txt> <toc_printed.txt> <toc.txt>

A scanned book's PDF pages do not carry the numbers printed on them: the
front matter comes first, and title pages and plates have none. This reads
each page's printed number from the OCR text (convert_to_pdf.sh's ocr.txt,
a form feed between pages), so the contents can be typed as the book prints
them:

    # toc_printed.txt: a title, a tab, its page; four spaces a level
    Preface	=4
    Part 1: Foundations	-
        1 Why Maps Matter	1
            Reading a Map	2

The page is the printed number, or "=4" for PDF page 4 (an entry with no
printed number or a roman one, or one the mapping gets wrong), or "-" for
one not placed yet. A title is the bookmark as it will read; a chapter
number or "Part 1: ", "Chapter 2: ", "Appendix A: " in front of it is left
out when it is looked for on its page.

A page's number is a line of digits alone among its first or last two
lines, kept only if a page within three of it agrees on the offset (PDF
page minus printed number). Pages between two that agree are filled in,
and the first offset is carried back to printed page 1. Every entry is then
looked for on the page it lands on, and printed with how well it was found:

    ok   1.00 pdf  19 printed   2 Reading a Map
    LOOK 0.67 pdf 222 printed 203 12 Drawing Your Own

LOOK is a heading the OCR text of that page does not hold: often display
type the OCR garbles, sometimes the wrong page, so each one is for a pair
of eyes. An entry that cannot be placed ("-", or a printed number no page
shows) is named, nothing is written, and the exit status is 1.
"""

# A script invoked by path, no license header.
# ruff: noqa: CPY001

import argparse
import difflib
import itertools
import re
import sys
from pathlib import Path

LINES_SEARCHED = 2
NEIGHBOURS = 3
FOUND = 0.8
# What a contents entry has in front of the heading as the page prints it.
LABEL = re.compile(r"^(\d+ |(Part|Chapter|Appendix) \w+: )")


class TocError(Exception):
    """An input this script will not guess its way around."""


def printed_number(text: str) -> int | None:
    """Return the page number printed on a page, if its OCR text shows one."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in lines[:LINES_SEARCHED] + lines[-LINES_SEARCHED:]:
        if re.fullmatch(r"\d{1,4}", line):
            return int(line)
    return None


def page_map(pages: list[str]) -> tuple[dict[int, int], list[tuple[int, int]]]:
    """Return each printed number's PDF page, and where the offset changes."""
    offsets = {}
    for pdf_page, text in enumerate(pages, start=1):
        number = printed_number(text)
        if number is not None:
            offsets[pdf_page] = pdf_page - number
    agreed = {
        page: offset
        for page, offset in offsets.items()
        if any(
            offsets.get(near) == offset
            for near in range(page - NEIGHBOURS, page + NEIGHBOURS + 1)
            if near != page
        )
    }
    if not agreed:
        msg = (
            f"no printed page numbers found in the OCR text of {len(pages)} pages; "
            "give every entry its PDF page as =N"
        )
        raise TocError(msg)
    known = sorted(agreed)
    pdf_of = {}
    for a, b in itertools.pairwise(known):
        if agreed[a] == agreed[b]:
            for page in range(a, b + 1):
                pdf_of[page - agreed[a]] = page
    for page in known:
        pdf_of.setdefault(page - agreed[page], page)
    first = known[0]
    for printed in range(1, first - agreed[first]):
        pdf_of.setdefault(printed, printed + agreed[first])
    changes = [
        (page, agreed[page])
        for i, page in enumerate(known)
        if i == 0 or agreed[page] != agreed[known[i - 1]]
    ]
    return pdf_of, changes


def squashed(text: str) -> str:
    """Return the letters and digits of a text, lower case, nothing between."""
    return re.sub(r"[^a-z0-9]", "", text.lower())


def how_found(title: str, text: str) -> float:
    """Return how well a page's OCR text holds a heading, 1.0 being exactly."""
    want, have = squashed(LABEL.sub("", title)), squashed(text)
    if want in have:
        return 1.0
    best = 0.0
    for start in range(0, max(1, len(have) - len(want) + 1), 3):
        piece = have[start : start + len(want)]
        best = max(best, difflib.SequenceMatcher(None, want, piece).ratio())
    return best


def entries(path: Path) -> list[tuple[int, str, str]]:
    """Read toc_printed.txt as (indent, title, page as written)."""
    found = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        title, tab, number = line.rstrip().rpartition("\t")
        indent = len(title) - len(title.lstrip(" "))
        if not tab or indent % 4 or not re.fullmatch(r"=?\d+|-", number):
            msg = (
                f"{path}:{n}: want a title, a tab and a printed page number, =N "
                f"or -, indented by fours: {line!r}"
            )
            raise TocError(msg)
        found.append((indent, title.strip(), number))
    return found


def work(args: argparse.Namespace) -> int:
    """Map every entry, report on each, and write the toc if all are placed."""
    pages = args.ocr.read_text(encoding="utf-8").split("\f")
    if pages and not pages[-1].strip():
        pages.pop()
    contents = entries(args.printed)
    pdf_of, changes = page_map(pages)
    say = sys.stdout.write
    say(f"{len(pages)} pages; PDF page minus printed number, from PDF page: ")
    say(", ".join(f"{page}: {offset}" for page, offset in changes) + "\n")
    lines, unplaced, to_look_at = [], 0, 0
    for indent, title, number in contents:
        if number.startswith("="):
            page = int(number[1:])
            if not 1 <= page <= len(pages):
                msg = f"{title!r} is at {number}; the PDF has pages 1 to {len(pages)}"
                raise TocError(msg)
        else:
            page = None if number == "-" else pdf_of.get(int(number))
        if page is None:
            say(f"UNPLACED printed {number:>3} {title}\n")
            unplaced += 1
            continue
        score = how_found(title, pages[page - 1])
        to_look_at += score < FOUND
        mark = "ok  " if score >= FOUND else "LOOK"
        say(f"{mark} {score:.2f} pdf {page:3d} printed {number:>3} {title}\n")
        quoted = title.replace('"', '""')
        lines.append(f'{" " * indent}"{quoted}" {page}')
    if unplaced:
        say(f"{unplaced} entries not placed: give each its PDF page as =N\n")
        return 1
    args.toc.write_text("\n".join(lines) + "\n", encoding="utf-8")
    say(f"wrote {args.toc}: {len(lines)} entries, {to_look_at} to look at\n")
    return 0


def main(argv: list[str]) -> int:
    """Run from the command line; 0 when the toc was written."""
    parser = argparse.ArgumentParser(
        prog="toc_pages.py",
        description="Map a book's contents from printed page numbers to PDF pages.",
    )
    parser.add_argument("ocr", type=Path, help="the OCR text, a form feed a page")
    parser.add_argument("printed", type=Path, help="the contents by printed page")
    parser.add_argument("toc", type=Path, help="the toc.txt to write, for pdftocio")
    try:
        return work(parser.parse_args(argv))
    except TocError as e:
        sys.stderr.write(f"toc_pages.py: {e}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
