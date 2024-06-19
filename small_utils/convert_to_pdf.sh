#!/usr/bin/env bash

# This script uses output of ScanTailor Advanced to create one pdf

# sudo apt install imagemagick poppler-utils ocrmypdf mediainfo

# pip install -U --user pdf.tocgen pymupdf==1.24.2

input_folder="$1"

out_folder="$input_folder/out_pdf"

rm -rf "$out_folder"

mkdir -p "$out_folder"

(
N=8 # num parallel tasks

for f in "$input_folder"/*.tif; do 
  ((i=i%N)); ((i++==0)) && wait

  filename=$(basename -- "$f")
  extension="${filename##*.}"
  filename="${filename%.*}"
  size=$(stat -c%s "$f")
  if [ $size -ge 200000 ] && mediainfo "$f" | grep RGB > /dev/null; then
    convert -quality 20 -compress JPEG "$f" "$out_folder/$filename.pdf" &
    echo "$filename" $size yes_convert_JPEG
  else
    convert "$f" "$out_folder/$filename.pdf" &
    echo "$filename" $size no_convert_JPEG
  fi
done
wait
)

pdfunite "$out_folder/"*.pdf "$out_folder/out.pdf"
ocrmypdf "$out_folder/out.pdf" "$out_folder/out_ocr.pdf"
# pdftocio "$out_folder/out_ocr.pdf" < toc.txt
