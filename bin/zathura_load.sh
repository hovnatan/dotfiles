#!/bin/bash

INPUT_DIR="$HOME/Dropbox/scripts/zathura/saves"
FILES=""
for filename in "$INPUT_DIR"/*; do
  fbase=$(basename "$filename")
  FILES="$FILES|$fbase"
done
FILES="${FILES:1}"
INPUT_FILE=$(echo "$FILES" | rofi -sep '|' -dmenu -p "Load filename > ")
INPUT_FILE="$INPUT_DIR/$INPUT_FILE"

if [ ! -f "$INPUT_FILE" ]; then
  dunstify -t 5000 "Wrong filename $INPUT_FILE."
  exit 1
fi

IFS=:
cat "$INPUT_FILE" | while read line
do
  read filename pagenumber <<< "$line"
  ((++pagenumber))
  zathura -P "$pagenumber" "$filename" &
done
