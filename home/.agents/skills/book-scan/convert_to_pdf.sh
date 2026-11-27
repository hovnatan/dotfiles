#!/usr/bin/env bash

# convert_to_pdf.sh <scantailor-output-folder> <pdf-folder>
#
# ScanTailor's TIFFs as one searchable PDF: step 5 of the book-scan skill,
# SKILL.md beside it. Written into <pdf-folder>, made if it is not there:
#   ocr.pdf   every page in name order, with a text layer
#   ocr.txt   that text, a form feed between pages
# A book.pdf there (ocr.pdf with bookmarks, the skill's last step) is
# removed: it was made from the ocr.pdf this run replaces.
#
# Needs mediainfo, magick (ImageMagick), pdfunite (poppler) and ocrmypdf on
# PATH. Where ocrmypdf is not installed and Nix is, run the script inside
#   nix shell nixpkgs#ocrmypdf -c \
#     env TMPDIR="$TMPDIR" bash <this script> <the two folders>
# TMPDIR is passed through because nix shell clears it, and every page then
# fails in tesseract.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <scantailor-output-folder> <pdf-folder>" >&2
  exit 1
fi

missing=()
for cmd in mediainfo magick pdfunite ocrmypdf; do
  command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "error: not on PATH: ${missing[*]} (see the top of $0)" >&2
  exit 1
fi

ulimit -n 10000

input_folder="$1"
pdf_folder="$2"

tiffs=("$input_folder"/*.tif)
[ -e "${tiffs[0]}" ] || {
  echo "error: no .tif in $input_folder; ScanTailor's output folder is wanted" >&2
  exit 1
}

mkdir -p "$pdf_folder"
rm -f "$pdf_folder/ocr.pdf" "$pdf_folder/ocr.txt" "$pdf_folder/book.pdf"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

at_a_time=8
i=0
for f in "${tiffs[@]}"; do
  if ((i++ % at_a_time == 0)); then wait; fi
  name=$(basename "$f" .tif)
  size=$(($(wc -c <"$f")))
  # Colour pages (cover, plates) as JPEG; bitonal and small ones as they are.
  if [ "$size" -ge 200000 ] && [[ $(mediainfo "$f") == *RGB* ]]; then
    magick "$f" -quality 85 -compress JPEG "$work/$name.pdf" &
    echo "$name $size yes_convert_JPEG"
  else
    magick "$f" "$work/$name.pdf" &
    echo "$name $size no_convert_JPEG"
  fi
done
wait

# A magick that failed in the background stops nothing; its page is missing.
pages=("$work"/*.pdf)
[ ${#pages[@]} -eq ${#tiffs[@]} ] || {
  echo "error: ${#tiffs[@]} TIFFs but ${#pages[@]} page PDFs; magick's errors are above" >&2
  exit 1
}
pdfunite "${pages[@]}" "$work/joined.pdf"
ocrmypdf "$work/joined.pdf" \
  -l eng \
  --output-type pdf \
  --sidecar "$pdf_folder/ocr.txt" \
  "$pdf_folder/ocr.pdf"
echo "wrote $pdf_folder/ocr.pdf (${#tiffs[@]} pages) and ocr.txt"
