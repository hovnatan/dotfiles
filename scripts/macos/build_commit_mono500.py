"""Build home/Library/Fonts/CommitMono500-*.otf, iTerm2's font.

Commit Mono ships only weights 400/700 as a family (Homebrew
font-commit-mono); other weights exist upstream as raw FontLab exports
(src/fonts/fontlab/CommitMonoV143-<weight><Regular|Italic>.otf), one
family per file, every file styled "Regular" and weight class 400. macOS
cannot link those into bold/italic siblings: asking for bold of the 500
returned the 500 itself, so iTerm2 drew fake bold. This relinks four
exports into one 4-style family, as the commitmono.com builder does:

    CommitMonoV143-500Regular -> CommitMono500-Regular      (weight 500)
    CommitMonoV143-500Italic  -> CommitMono500-Italic       (weight 500)
    CommitMonoV143-700Regular -> CommitMono500-Bold         (weight 700)
    CommitMonoV143-700Italic  -> CommitMono500-BoldItalic   (weight 700)

Only names and style bits change; glyphs are untouched. OFL 1.1 with no
Reserved Font Name, so a renamed modified version may be redistributed
with the licence (CommitMono500-OFL.txt).

Rebuild (built 2026-09-25 from upstream d407cd2bf8e0):

    src=$(mktemp -d)
    for f in 500Regular 500Italic 700Regular 700Italic; do
      curl -fsSL -o "$src/CommitMonoV143-$f.otf" \\
        "https://raw.githubusercontent.com/eigilnikolajsen/commit-mono/d407cd2bf8e01ca1db70544052fbbb9606406c3b/src/fonts/fontlab/CommitMonoV143-$f.otf"
    done
    uvx --from fonttools python scripts/macos/build_commit_mono500.py "$src" home/Library/Fonts
"""

import sys

from fontTools.ttLib import TTFont

FAMILY = "CommitMono500"

# source file -> (style, bold, italic, weight class)
STYLES = {
    "CommitMonoV143-500Regular.otf": ("Regular", False, False, 500),
    "CommitMonoV143-500Italic.otf": ("Italic", False, True, 500),
    "CommitMonoV143-700Regular.otf": ("Bold", True, False, 700),
    "CommitMonoV143-700Italic.otf": ("Bold Italic", True, True, 700),
}


def main(src: str, out: str) -> None:
    for fn, (style, bold, italic, weight) in STYLES.items():
        f = TTFont(f"{src}/{fn}")
        ps = f"{FAMILY}-{style.replace(' ', '')}"
        full = f"{FAMILY} {style}"

        # name table: legacy 4-style linking (IDs 1/2) is what macOS uses
        # to find the bold/italic siblings; drop the typographic IDs 16/17
        # that carried the per-weight names ("500 Regular").
        name = f["name"]
        for nid in (16, 17):
            name.removeNames(nameID=nid)
        for nid, val in (
            (1, FAMILY),
            (2, style),
            (3, f"{ps};V143"),
            (4, full),
            (6, ps),
        ):
            name.setName(val, nid, 3, 1, 0x409)
            name.setName(val, nid, 1, 0, 0)

        # CFF carries its own copy of the names.
        cff = f["CFF "].cff
        cff.fontNames = [ps]
        td = cff.topDictIndex[0]
        td.FullName, td.FamilyName = full, FAMILY
        td.Weight = "Bold" if bold else "Regular"

        # Weight class and style bits: fsSelection bit 0 italic, 5 bold,
        # 6 regular; head.macStyle bit 0 bold, 1 italic.
        os2 = f["OS/2"]
        os2.usWeightClass = weight
        sel = os2.fsSelection & ~(1 | 1 << 5 | 1 << 6)
        sel |= (1 if italic else 0) | (1 << 5 if bold else 0)
        if not (bold or italic):
            sel |= 1 << 6
        os2.fsSelection = sel
        f["head"].macStyle = (1 if bold else 0) | (2 if italic else 0)

        f.save(f"{out}/{ps}.otf")
        print(f"{fn} -> {ps}.otf (weight {weight})", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(
            "usage: build_commit_mono500.py <dir with CommitMonoV143 exports> <out dir>"
        )
    main(sys.argv[1], sys.argv[2])
