#!/bin/bash

INPUT_FILE="$HOME/Dropbox/scripts/zathura/zathura_save"
SYNCED=""
i=0
while [ "$SYNCED" == "" ] && [ $i -lt 10 ] ; do
  sleep 0.5
  SYNCED=$("$HOME/Dropbox/scripts/dropbox.py" filestatus "$INPUT_FILE" | grep -- "up to date")
  ((i=i+1))
done

IFS=:
cat "$INPUT_FILE" | while read line
do
  read filename pagenumber <<< "$line"
  ((++pagenumber))
  zathura -P "$pagenumber" "$filename" &
done
