#!/bin/bash

basename=$(basename -- "$1")
extension="${basename##*.}"
filename="${basename%.*}"

if [ "$extension" = "md" ]; then
  tmp_file="/tmp/output-md.html"
  pandoc -f gfm -t html -c "$HOME/.dotfiles/.config/nvim/pandoc.css" -s -o "$tmp_file"  $1
  chromium "$tmp_file"
else
  texfile="$1"
  pdflatex -output-directory /tmp "$texfile"

  fn_pdf="/tmp/${filename}.pdf"
  wid=$(xdotool search --name "${fn_pdf}")

  if test -z "$wid"; then
    setsid zathura ${fn_pdf}
    xdotool search --name "${fn}" windowactivate
  else
    xdotool key --window $wid 'R'
  fi
fi

