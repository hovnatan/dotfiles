#!/usr/bin/env bash
#
# toc_pages_test.sh -- the book-scan skill's toc_pages.py
# (home/.agents/skills/book-scan/toc_pages.py), on the OCR text of a made-up
# book of 26 PDF pages. Needs python3; about 1 s.
#
#   PDF page  what its OCR text holds
#   1-3       front matter, no number (2 is the preface)
#   4-13      printed 1-10, the number the first line; 6's is misread as 99;
#             4 opens both the part and its first chapter
#   14        a title page with no number
#   15-26     printed 11-22, the number the last line
#
#   mapping     an entry before, at and after the page with no number lands
#               on its page: offsets 3 and 4, the misread 99 left out
#   front       an entry with no printed number takes its PDF page as =N;
#   matter      left at "-" it is named, nothing is written, exit 1
#   look        a heading its page does not hold is marked LOOK, and still
#               written
#   quotes      a title with double quotes reads back from the toc as typed
#   refusals    =N past the last page; a line with no tab
#
# Exit 0 = all passed; on failure the work dir is kept and printed.
set -uo pipefail

command -v python3 >/dev/null || {
  echo "toc_pages_test.sh: python3 not on PATH" >&2
  exit 1
}

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
SCRIPT="$REPO/home/.agents/skills/book-scan/toc_pages.py"
WORK=$(mktemp -d)
trap drop_work EXIT

python3 - "$WORK/ocr.txt" <<'EOF'
import sys

headings = {1: "FOUNDATIONS\nWHY MAPS MATTER", 3: "Reading a Map", 12: 'Explaining "How to"', 20: "Index"}
pages = ["THE BOOK", "PREFACE\nIn 1973 I published", "CONTENTS"]
for printed in range(1, 23):
    body = headings.get(printed, "body text of the page")
    shown = 99 if printed == 3 else printed
    if printed == 11:
        pages.append("PART TWO")
    pages.append(f"{shown}\n{body}\nmore" if printed <= 10 else f"{body}\nmore\n{shown}")
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("\f".join(pages) + "\f")
EOF

contents() {
  printf '%s\n' \
    '# a made-up book' \
    "Preface"$'\t'"$1" \
    $'Part 1: Foundations\t1' \
    $'    1 Why Maps Matter\t1' \
    $'        Reading a Map\t3' \
    $'        Explaining "How to"\t12' \
    $'    2 A Heading Not There\t15' \
    $'Index\t20'
}
contents "=2" >"$WORK/printed.txt"
contents - >"$WORK/unplaced.txt"
contents "=27" >"$WORK/past.txt"

run() { python3 "$SCRIPT" "$WORK/ocr.txt" "$@" >"$WORK/out" 2>&1; }

if run "$WORK/printed.txt" "$WORK/toc.txt"; then
  want=$'"Preface" 2\n"Part 1: Foundations" 4\n    "1 Why Maps Matter" 4\n        "Reading a Map" 6\n        "Explaining ""How to""" 16\n    "2 A Heading Not There" 19\n"Index" 24'
  if [ "$(cat "$WORK/toc.txt")" = "$want" ]; then
    pass "mapping: entries before, at and after the unnumbered page"
  else
    fail "mapping: $(cat "$WORK/toc.txt")"
  fi
  if grep -q "from PDF page: 4: 3, 15: 4$" "$WORK/out"; then
    pass "mapping: offsets 3 then 4, the misread number left out"
  else
    fail "mapping: $(head -1 "$WORK/out")"
  fi
  if grep -q "^LOOK .* pdf  19 printed  15 2 A Heading Not There$" "$WORK/out" \
    && [ "$(grep -c '^LOOK' "$WORK/out")" -eq 1 ] \
    && grep -q "7 entries, 1 to look at$" "$WORK/out"; then
    pass "look: the one heading its page does not hold is marked"
  else
    fail "look: $(cat "$WORK/out")"
  fi
  title=$(python3 -c 'import csv, sys
rows = list(csv.reader(open(sys.argv[1]), delimiter=" ", quoting=csv.QUOTE_NONNUMERIC))
print(rows[4][8])' "$WORK/toc.txt")
  if [ "$title" = 'Explaining "How to"' ]; then
    pass "quotes: a quoted title reads back as typed"
  else
    fail "quotes: read back as $title"
  fi
else
  fail "mapping: exit $?: $(cat "$WORK/out")"
fi

rm -f "$WORK/toc.txt"
if run "$WORK/unplaced.txt" "$WORK/toc.txt"; then
  fail "front matter: an entry with no page was accepted"
elif grep -q "^UNPLACED printed   - Preface$" "$WORK/out" && [ ! -e "$WORK/toc.txt" ]; then
  pass "front matter: the unplaced entry is named and nothing is written"
else
  fail "front matter: $(cat "$WORK/out")"
fi

if run "$WORK/past.txt" "$WORK/toc.txt"; then
  fail "refusals: =27 in a PDF of 26 pages was accepted"
elif grep -q "'Preface' is at =27; the PDF has pages 1 to 26" "$WORK/out"; then
  pass "refusals: =N past the last page"
else
  fail "refusals: $(cat "$WORK/out")"
fi

echo "Index 20" >"$WORK/bad.txt"
if run "$WORK/bad.txt" "$WORK/toc.txt"; then
  fail "refusals: a line with no tab was accepted"
elif grep -q "bad.txt:1: want a title, a tab" "$WORK/out"; then
  pass "refusals: a line with no tab, named by file and line"
else
  fail "refusals: $(cat "$WORK/out")"
fi

finish
