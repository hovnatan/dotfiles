"""Move a prefix's .jpeg pages to another folder, numbered in reverse order.

For a book scanned back to front: the pages of one prefix, in name order,
come out numbered from the last, so name order is reading order again.

    in  --path:         a_001.jpeg a_002.jpeg a_003.jpeg b_001.jpeg
    out --output_path:  a_002.jpeg a_001.jpeg a_000.jpeg   (--prefix a)

A file's prefix is its name up to the first "_". Files are moved, not
copied. Every check runs before the first move, so a refused run leaves
both folders as they were.
"""

# ruff: noqa: INP001, CPY001

import argparse
from pathlib import Path

# The new numbers are zero-padded to this many digits, so that name order
# is number order; more pages than that would break it.
DIGITS = 3


def reverse_names(path: Path, prefix: str, output_path: Path) -> None:
    """Move `prefix`'s .jpeg files from `path` to `output_path`, numbered in reverse."""
    if not path.is_dir():
        msg = f"--path {path} is not a directory"
        raise SystemExit(msg)
    pages = [f for f in sorted(path.glob("*.jpeg")) if f.stem.split("_")[0] == prefix]
    if not pages:
        msg = f"no {prefix}_*.jpeg in {path}"
        raise SystemExit(msg)
    if len(pages) > 10**DIGITS:
        msg = f"{len(pages)} pages, but numbers have {DIGITS} digits"
        raise SystemExit(msg)

    # Last page first: a_003 -> a_000. A name already taken in the output
    # folder is an error, since rename() would overwrite it.
    moves = [
        (page, output_path / f"{prefix}_{len(pages) - i - 1:0{DIGITS}d}.jpeg")
        for i, page in enumerate(pages)
    ]
    if taken := [str(new) for _, new in moves if new.exists()]:
        msg = f"{len(taken)} names already in {output_path}: {', '.join(taken)}"
        raise SystemExit(msg)

    output_path.mkdir(parents=True, exist_ok=True)
    print(f"moving {len(moves)} {prefix} pages to {output_path}", flush=True)  # noqa: T201
    for page, new in moves:
        page.rename(new)
        print(f"{page.name} -> {new.name}", flush=True)  # noqa: T201


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--path",
        type=Path,
        required=True,
        help="directory holding the images",
    )
    parser.add_argument(
        "--prefix",
        required=True,
        help='the pages\' name up to the first "_"',
    )
    parser.add_argument(
        "--output_path",
        type=Path,
        required=True,
        help="directory to move the renumbered images to",
    )
    args = parser.parse_args()
    reverse_names(args.path, args.prefix, args.output_path)
