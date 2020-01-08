#!/bin/bash

PIDS=$(pidof zathura)
if [ "$PIDS" == "" ]; then
  exit 0
fi
OUTPUT_DIR="$HOME/Dropbox/scripts/zathura/saves"
if [ "$1" == "" ]; then
  FILES=""
  for filename in "$OUTPUT_DIR"/*; do
    fbase=$(basename "$filename")
    FILES="$FILES|$fbase"
  done
  FILES="${FILES:1}"
  OUTPUT_FILE=$(echo "$FILES" | rofi -sep '|' -dmenu -p "Save to filename > ")
  if [ "$OUTPUT_FILE" == "" ]; then
    dunstify -t 5000 "Wrong filename."
    exit 1
  fi
else
  OUTPUT_FILE="$1"
  if [ "$2" != "" ]; then
    OUTPUT_FILE="${OUTPUT_FILE}_$(hostname)"
  fi
fi
OUTPUT_FILE="$OUTPUT_DIR/$OUTPUT_FILE"

rm -f "$OUTPUT_FILE"
touch "$OUTPUT_FILE"

for PID in $PIDS; do
  filename=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:filename | grep -oP ".*variant.*string\s+\"\K(.*)(?=\")")
  pagenumber=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:pagenumber | grep -oP ".*variant.*uint32\s+\K(.*)")
  echo "$filename:$pagenumber" >> "$OUTPUT_FILE"
done
sort -o "$OUTPUT_FILE" "$OUTPUT_FILE"

SYNCED=""
i=0
while [ "$SYNCED" == "" ] && [ $i -lt 10 ] ; do
  sleep 0.5
  SYNCED=$("$HOME/Dropbox/scripts/dropbox.py" filestatus "$OUTPUT_FILE" | grep -- "up to date")
  ((i=i+1))
done

if [ "$SYNCED" == "" ]; then
  dunstify -t 5000 -u c "Couldn't Dropbox sync zathura file at $OUTPUT_FILE."
else
  dunstify -t 5000 "Dropbox synced zathura file at $OUTPUT_FILE."
fi
