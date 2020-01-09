#!/bin/bash

INPUT_DIR="$HOME/Dropbox/scripts/zathura/saves"
if [[ "$1" == "" || "$1" == "load_from_rofi" ]]; then
  FILES=""
  for filename in "$INPUT_DIR"/*; do
    fbase=$(basename "$filename")
    FILES="$FILES|$fbase"
  done
  FILES="${FILES:1}"
  INPUT_FILE=$(echo "$FILES" | rofi -sep '|' -dmenu -p "Load filename > ")
  INPUT_FILE="$INPUT_DIR/$INPUT_FILE"
else
  INPUT_FILE="$1"
fi

if [ ! -f "$INPUT_FILE" ]; then
  dunstify -t 5000 "Wrong filename $INPUT_FILE."
  exit 1
fi

i3-msg layout tabbed

IFS=:
cat "$INPUT_FILE" | while read line
do
  read filename pagenumber workspace <<< "$line"
  ((++pagenumber))
  zathura -P "$pagenumber" "$filename" &
  sleep 0.5
done
