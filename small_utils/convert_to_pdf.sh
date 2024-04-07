#!/usr/bin/env bash

sudo apt install imagemagick poppler-utils ocrmypdf

mkdir -p out_pdf

for f in *.tif; do 
  filename=$(basename -- "$f")
  extension="${filename##*.}"
  filename="${filename%.*}"
  echo "$filename"
  convert "$f" "out_pdf/${filename}.pdf"
done


pdfunite out_pdf/*.pdf ./out.pdf
ocrmypdf ./out.pdf ./out_ocr.pdf