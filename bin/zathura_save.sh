#!/bin/bash

PIDS_WS=$(python ~/.dotfiles/bin/zathura_get_windows.py)
if [ "$PIDS_WS" == "" ]; then
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

WSS=()
IFS=:
while read line
do
  read PID WS <<< "$line"
  if [[ "${WSS[@]}" =~ "${WS}" ]]; then
    continue
  fi
  WSS+=( "$WS" )
  OUTPUT_FILE_WS="${OUTPUT_FILE}_$WS"
  rm -f "$OUTPUT_FILE_WS"
  touch "$OUTPUT_FILE_WS"
done <<< "$PIDS_WS"

while read line
do
  read PID WS <<< "$line"
  OUTPUT_FILE_WS="${OUTPUT_FILE}_$WS"

  filename=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:filename | grep -oP ".*variant.*string\s+\"\K(.*)(?=\")")
  pagenumber=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:pagenumber | grep -oP ".*variant.*uint32\s+\K(.*)")
  echo "$filename:$pagenumber:$WS" >> "$OUTPUT_FILE_WS"
done <<< "$PIDS_WS"

for WS in "${WSS[@]}"; do
  OUTPUT_FILE_WS="${OUTPUT_FILE}_$WS"
  sort -o "$OUTPUT_FILE_WS" "$OUTPUT_FILE_WS"
done

COUNT_TO_SYNC=${#WSS[@]}
SYNCED_WS=()
i=0
while [ ${#SYNCED_WS[@]} != $COUNT_TO_SYNC ] && [ $i -lt 10 ] ; do
  sleep 0.5
  for WS in "${WSS[@]}"; do
    if [[ " ${SYNCED_WS[@]} " =~ "${WS}" ]]; then
      continue
    fi
    OUTPUT_FILE_WS="${OUTPUT_FILE}_$WS"
    STATUS=$("$HOME/Dropbox/scripts/dropbox.py" filestatus "$OUTPUT_FILE_WS" | grep -- "up to date")
    if [ "$STATUS" != "" ]; then
      SYNCED_WS+=( "$WS" )
    fi
  done
  ((i=i+1))
done

if [ ${#SYNCED_WS[@]} != $COUNT_TO_SYNC ]; then
  dunstify -t 5000 -u c "Couldn't Dropbox sync zathura file at $OUTPUT_FILE."
else
  dunstify -t 5000 "Dropbox synced zathura file at $OUTPUT_FILE."
fi
