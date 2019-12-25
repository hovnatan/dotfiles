#!/bin/bash

INPUT_FILE="$HOME/Dropbox/zathura_save"

IFS=:
cat "$INPUT_FILE" | while read line
do
  read filename pagenumber <<< "$line"
  ((++pagenumber))
  zathura -P "$pagenumber" "$filename" &
done
