#!/bin/bash

INPUT_DIR="$HOME/Dropbox/scripts/zathura/saves"
if [[ "$1" == "" || "$1" == "load_from_rofi" ]]; then
  FILES=""
  FILEPATHS=()
  for FILENAME in "$INPUT_DIR"/*; do
    FILEPATHS+=( "$FILENAME" )
    MOD_TIME=$(date -r "$FILENAME" "+%m/%d/%Y %H:%M:%S")
    FBASE=$(basename "$FILENAME")
    printf -v TEXT "%-35s%37s" "$FBASE" "$MOD_TIME"
    FILES="$FILES|$TEXT"
  done
  FILES="${FILES:1}"
  INDEX=$(echo "$FILES" | rofi -width -75 -sep '|' -dmenu -p "Load filename > " -format i)
  if [[ $INDEX != "" ]]; then
    INPUT_FILE=${FILEPATHS[$INDEX]}
  fi
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
