#!/bin/bash

basename=$(basename -- "$1")
extension="${basename##*.}"
filename="${basename%.*}"

if [ "$extension" = "md" ]; then 
  texfile=/tmp/"${filename}.tex"
  pandoc --template=default.latex -s $1 -o "$texfile"
else
  texfile="$1"
fi

pdflatex -output-directory /tmp "$texfile"

fn_pdf="/tmp/${filename}.pdf"
wid=$(xdotool search --name "${fn_pdf}")

if test -z "$wid"; then
    setsid zathura ${fn_pdf}
    xdotool search --name "${fn}" windowactivate
else
    xdotool key --window $wid 'R'
fi
