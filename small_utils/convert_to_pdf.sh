#!/usr/bin/env bash

# sudo apt install imagemagick poppler-utils ocrmypdf mediainfo

# sudo vim /etc/ImageMagick-6/policy.xml # remove lines disabling PDF  also maybe increase memory and disk resources size

input_folder="."

out_folder="out_pdf"

rm -rf "$out_folder"

mkdir -p "$out_folder"

N=8 # num parallel tasks

(
for f in "$input_folder"/*.tif; do 
  ((i=i%N)); ((i++==0)) && wait

  filename=$(basename -- "$f")
  extension="${filename##*.}"
  filename="${filename%.*}"
  size=$(stat -c%s "$f")
  if [ $size -ge 300000 ] && mediainfo "$f" | grep RGB > /dev/null; then
    convert -quality 20 -compress JPEG "$f" "$out_folder/$filename.pdf" &
    echo "$filename" $size yes_convert_JPEG
  else
    convert "$f" "$out_folder/$filename.pdf" &
    echo "$filename" $size no_convert_JPEG
  fi
done
)
wait

pdfunite "$out_folder/"*.pdf ./out.pdf
ocrmypdf ./out.pdf ./out_ocr.pdf