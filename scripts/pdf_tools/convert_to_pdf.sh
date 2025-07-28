#!/usr/bin/env bash

# This script uses output of ScanTailor Advanced to create one pdf

# sudo apt install imagemagick poppler-utils ocrmypdf mediainfo jbig2

# for macos
# brew install imagemagick poppler ocrmypdf mediainfo
# ulimit -n 10000

# pip install -U --user pdf.tocgen pymupdf==1.24.2

# Function to convert TIFF files to PDF in parallel
convert_tiffs_to_pdf() {
    local input_folder="$1"
    local out_folder="$2"
    local N=8 # num parallel tasks
    local i=0

    for f in "$input_folder"/*.tif; do 
        ((i=i%N)); ((i++==0)) && wait

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
            magick -quality 20 -compress JPEG "$f" "$out_folder/$filename.pdf" &
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
ocrmypdf "$out_folder/out.pdf" --output-type pdf "$out_folder/out_ocr.pdf"
uvx --from=pdf.tocgen pdftocio "$out_folder/out_ocr.pdf" < toc.txt
