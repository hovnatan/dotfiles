#!/bin/bash

INPUT_FILE="$HOME/Dropbox/zathura_save"
SYNCED=""
while [ "$SYNCED" == "" ] ; do
  sleep 0.5
  SYNCED=$("$HOME/Dropbox/scripts/dropbox.py" filestatus "$OUTPUT_FILE" | grep -- "up to date")
done

IFS=:
cat "$INPUT_FILE" | while read line
do
  read filename pagenumber <<< "$line"
  ((++pagenumber))
  zathura -P "$pagenumber" "$filename" &
done
