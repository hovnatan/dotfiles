#!/usr/bin/env bash

# This script uses output of ScanTailor to create one pdf

# for Ubuntu Linux
# sudo apt install imagemagick poppler-utils ocrmypdf mediainfo jbig2
# sudo apt install scantailor

# for MacOS
# brew install imagemagick poppler ocrmypdf mediainfo jbig2
# ScanTailor itself is NOT in Homebrew -- it comes from MacPorts:
#   sudo port install scantailor

# NB: deliberately not "set -e". The parallel loop below relies on arithmetic
# expansions that evaluate to 0, which bash reports as exit status 1 -- with
# "set -e" the script would die at the first batch boundary.
set -uo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <scantailor-output-folder>" >&2
    exit 1
fi

ulimit -n 10000

# Function to convert TIFF files to PDF in parallel
convert_tiffs_to_pdf() {
    local input_folder="$1"
    local out_folder="$2"
    local N=8 # num parallel tasks
    local i=0

    for f in "$input_folder"/*.tif; do
        # "|| true" so these stay safe if "set -e" is ever added: both
        # expansions legitimately evaluate to 0, which bash calls failure.
        (( i = i % N )) || true
        (( i++ == 0 )) && wait || true

        filename=$(basename -- "$f")
        extension="${filename##*.}"
        filename="${filename%.*}"
        # Cross-platform file size detection
        if [[ "$OSTYPE" == "darwin"* ]]; then
            size=$(stat -f%z "$f")  # macOS/BSD
        else
            size=$(stat -c%s "$f")  # Linux/GNU
        fi
        if [ $size -ge 200000 ] && mediainfo "$f" | grep RGB > /dev/null; then
            # Colour pages (cover, plates). Quality 20 was visibly destroying
            # them; 85 is near-transparent and costs little, as bitonal text
            # pages take the branch below and are unaffected.
            magick "$f" -quality 85 -compress JPEG "$out_folder/$filename.pdf" &
            echo "$filename" $size yes_convert_JPEG
        else
            magick "$f" "$out_folder/$filename.pdf" &
            echo "$filename" $size no_convert_JPEG
        fi
    done
    wait
}

input_folder="$1"
out_folder="$input_folder/out_pdf"

rm -rf "$out_folder"
mkdir -p "$out_folder"

convert_tiffs_to_pdf "$input_folder" "$out_folder"
pdfunite "$out_folder/"*.pdf "$out_folder/out.pdf"
ocrmypdf "$out_folder/out.pdf" \
    -l eng \
    --output-type pdf \
    --sidecar "$out_folder/out_ocr.txt" \
    "$out_folder/out_ocr.pdf"
uvx --from=pdf.tocgen pdftocio "$out_folder/out_ocr.pdf" < "$input_folder/toc.txt"
