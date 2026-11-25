#!/usr/bin/env python3
r"""Turn picture subtitles (VobSub .idx/.sub) into a text .srt, by OCR.

    vobsub_to_srt.py [-l <language>] [-o <folder>] [--force] <name>.idx ...

Each <name>.idx, with its <name>.sub beside it, becomes <name>.<id>.srt:
<id> is the language the .idx names ("id: en"), and the file goes in
<folder>, or beside the .idx. A season whose pairs sit in a VobSub folder,
the text wanted beside the videos:

    vobsub_to_srt.py -o "Season 01" "Season 01/VobSub/"*.idx

mpv draws a text subtitle in the font and colour of mpv.conf; a picture one
keeps the look its disc gave it.

Two OCR programs, as neither does the whole job:

    <name>.idx + <name>.sub
      |  vobsub2srt --dump-images: an image per line, and an .srt whose
      |  timings are right but whose text is a 2014 build's on tesseract 3,
      v  which reads this kind of capital I as l or |
    <name>-001.pgm ... and the timings
      |  tesseract 5 on each image, 8 at a time
      v
    the text, its systematic misreadings put right (English only) --> .srt

Measured on 12 episodes, 5,518 lines (2026-11-25): about 20 garbled words
left in 22,750, and 4 lines tesseract returned nothing for at any page mode,
size or polarity, each the one word "I...". Such a line is left out of the
.srt and logged with its time, its image is kept in the run's log folder to
read by eye, and the exit status is 1: no line here is a guess.

Needs vobsub2srt and tesseract 5 on PATH: nix/flake.nix, the Mac's list.
"""

# A script invoked by path, no license header, as in scripts/.
# ruff: noqa: CPY001

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from event_log import EventLog

WORKERS = 8

# An entry of the .srt vobsub2srt writes: its number, from 0, then its times.
ENTRY = re.compile(
    r"^(\d+)\n(\d\d:\d\d:\d\d,\d{3} --> \d\d:\d\d:\d\d,\d{3})$",
    re.MULTILINE,
)
TRACK = re.compile(r"^id: (\w+), index: \d+", re.MULTILINE)

# What tesseract 5 gets wrong the same way each time in a sans-serif
# subtitle font, in order: a bar beside or for the capital I, the pronoun as
# a lone lowercase L, and the dash that opens a second speaker's line.
ENGLISH_FIXES = (
    (re.compile(r"\|I"), "I"),
    (re.compile(r"\|"), "I"),
    (re.compile(r"\bl\b"), "I"),
    (re.compile(r"\bI'l\b"), "I'll"),
    (re.compile(r"\b1(?=I')"), ""),
    (re.compile(r"\bIl (?=[a-z])"), "I "),
    (re.compile(r"^— ?", re.MULTILINE), "- "),
    (re.compile(r"—"), "-"),
)


class ConversionError(Exception):
    """A pair that cannot be converted, and why."""


@dataclass(frozen=True)
class Line:
    """One subtitle: vobsub2srt's number for it, its times, its image."""

    number: int
    timing: str
    image: Path


def run(command: list[str], cwd: Path | None = None) -> str:
    """Run a program to its end and return its stdout, raising if it failed."""
    r = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=False)  # noqa: S603 - our own arguments
    if r.returncode != 0:
        msg = f"{command[0]} exited {r.returncode}: {(r.stderr or r.stdout).strip()}"
        raise ConversionError(msg)
    return r.stdout


def track_id(idx: Path) -> str:
    """Return the language of the .idx's one track, as it names it."""
    ids = TRACK.findall(idx.read_text(encoding="utf-8", errors="replace"))
    if len(ids) != 1:
        msg = f"{idx}: {len(ids)} tracks, and only a single one is handled"
        raise ConversionError(msg)
    return ids[0]


def dump(idx: Path, work: Path) -> list[Line]:
    """Have vobsub2srt write an image per line into `work`, and return the lines."""
    # Under a name of our own: vobsub2srt takes the pair's name without its
    # ending, and writes beside it.
    shutil.copyfile(idx, work / "s.idx")
    shutil.copyfile(idx.with_suffix(".sub"), work / "s.sub")
    run(["vobsub2srt", "--dump-images", "s"], cwd=work)
    timed = (work / "s.srt").read_text(encoding="utf-8", errors="replace")
    entries = ENTRY.findall(timed)
    images = {int(p.stem.removeprefix("s-")): p for p in work.glob("s-*.pgm")}
    if sorted(images) != [int(n) + 1 for n, _ in entries]:
        msg = f"{idx}: vobsub2srt timed {len(entries)} lines, drew {len(images)}"
        raise ConversionError(msg)
    return [Line(int(n), timing, images[int(n) + 1]) for n, timing in entries]


def height(image: Path) -> int:
    """Return a PGM image's height: 0 for the marker vobsub2srt ends a track with."""
    magic, _width, rows = image.read_bytes().split(None, 3)[:3]
    if magic != b"P5":
        msg = f"{image}: not a binary PGM"
        raise ConversionError(msg)
    return int(rows)


def read_text(image: Path, language: str) -> str:
    """Return the text tesseract reads in an image, "" for an image of no height."""
    if height(image) == 0:
        return ""
    # Page mode 6: one block of text, which a subtitle of one to three lines is.
    text = run(["tesseract", str(image), "stdout", "--psm", "6", "-l", language])
    if language == "eng":
        for pattern, replacement in ENGLISH_FIXES:
            text = pattern.sub(replacement, text)
    return "\n".join(
        s for s in (raw.strip() for raw in text.replace("\f", "").splitlines()) if s
    )


def write_srt(path: Path, entries: list[tuple[str, str]]) -> None:
    """Write the (timing, text) entries as an .srt, whole or not at all."""
    partial = path.with_name(path.name + ".part")
    partial.write_text(
        "".join(
            f"{i}\n{timing}\n{text}\n\n" for i, (timing, text) in enumerate(entries, 1)
        ),
        encoding="utf-8",
    )
    partial.replace(path)


def convert(idx: Path, target: Path, language: str, log: EventLog) -> int:
    """Write `target` from the pair, and return how many lines could not be read."""
    with tempfile.TemporaryDirectory(prefix="vobsub_to_srt.") as tmp:
        lines = dump(idx, Path(tmp))
        with ThreadPoolExecutor(max_workers=min(WORKERS, os.cpu_count() or 1)) as pool:
            texts = list(pool.map(lambda line: read_text(line.image, language), lines))
        entries, unread = [], 0
        for line, text in zip(lines, texts, strict=True):
            if text:
                entries.append((line.timing, text))
            elif height(line.image) > 0:
                unread += 1
                kept = (
                    log.path.parent / "unread" / f"{idx.stem}-{line.number + 1:03d}.pgm"
                )
                kept.parent.mkdir(exist_ok=True)
                shutil.copyfile(line.image, kept)
                log.note(f"UNREAD {idx.name} at {line.timing}: left out, see {kept}")
    write_srt(target, entries)
    log.note(f"{idx.name} -> {target}: {len(entries)} lines, {unread} unread")
    return unread


def plan(idxs: list[Path], folder: Path | None, *, force: bool) -> list[Path]:
    """Return the .srt each .idx becomes, raising before anything is converted."""
    for program in ("vobsub2srt", "tesseract"):
        if shutil.which(program) is None:
            msg = f"{program} is not on PATH: nix/flake.nix has it, in the Mac's list"
            raise ConversionError(msg)
    targets = []
    for idx in idxs:
        if idx.suffix != ".idx" or not idx.is_file():
            msg = f"{idx}: not a .idx file"
            raise ConversionError(msg)
        if not idx.with_suffix(".sub").is_file():
            msg = f"{idx}: no {idx.with_suffix('.sub').name} beside it"
            raise ConversionError(msg)
        target = (folder or idx.parent) / f"{idx.stem}.{track_id(idx)}.srt"
        if not target.parent.is_dir():
            msg = f"{target.parent}: no such folder"
            raise ConversionError(msg)
        if target.exists() and not force:
            msg = f"{target} is already there: --force writes over it"
            raise ConversionError(msg)
        targets.append(target)
    return targets


def main(argv: list[str]) -> int:
    """Convert each pair argv names."""
    p = argparse.ArgumentParser(
        prog="vobsub_to_srt.py",
        description=(__doc__ or "").split("\n")[0],
    )
    p.add_argument("-l", dest="language", default="eng", help="tesseract's language")
    p.add_argument("-o", dest="folder", type=Path, help="where the .srt files go")
    p.add_argument("--force", action="store_true", help="write over an .srt")
    p.add_argument("idx", nargs="+", type=Path, help="a .idx, its .sub beside it")
    args = p.parse_args(argv)

    log = EventLog.start("vobsub_to_srt")
    try:
        targets = plan(args.idx, args.folder, force=args.force)
        unread = sum(
            convert(idx, target, args.language, log)
            for idx, target in zip(args.idx, targets, strict=True)
        )
    except ConversionError as e:
        log.note(f"FAILED: {e}")
        return 1
    if unread:
        log.note(f"{unread} lines left out, see UNREAD above")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
