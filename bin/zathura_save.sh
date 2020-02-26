#!/bin/bash

CURRENT_WORKSPACE=""
if [[ "$3" != "" ]]; then
  CURRENT_WORKSPACE=$(i3-msg -t get_workspaces \
  | jq '.[] | select(.focused==true).name' \
  | cut -d"\"" -f2)
fi

PIDS_WS_NAME=$(python ~/.dotfiles/bin/zathura_get_windows.py "$CURRENT_WORKSPACE")
if [ "$PIDS_WS_NAME" == "" ]; then
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

OUTPUT_FILE_NAMES=()
IFS=:
while read line
do
  read PID WS NAME <<< "$line"
  if [[ "$1" == "last" ]]; then
    OUTPUT_FILE_NAME="${OUTPUT_FILE}_$WS"
  else
    OUTPUT_FILE_NAME="${OUTPUT_FILE}"
  fi
  if [[ ! " ${OUTPUT_FILE_NAMES[@]} " =~ " ${OUTPUT_FILE_NAME} " ]]; then
    OUTPUT_FILE_NAMES+=( "$OUTPUT_FILE_NAME" )
    rm -f "$OUTPUT_FILE_NAME"
    touch "$OUTPUT_FILE_NAME"
  fi

  filename=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:filename | grep -oP ".*variant.*string\s+\"\K(.*)(?=\")")
  pagenumber=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:pagenumber | grep -oP ".*variant.*uint32\s+\K(.*)")
  printf -v OUTPUT_PAGENUMBER "%05d" $pagenumber
  echo "$filename:$OUTPUT_PAGENUMBER:$WS:$NAME" >> "$OUTPUT_FILE_NAME"
done <<< "$PIDS_WS_NAME"

for OUTPUT_FILE_NAME in "${OUTPUT_FILE_NAMES[@]}"; do
  sort -o "$OUTPUT_FILE_NAME" "$OUTPUT_FILE_NAME"
done

COUNT_TO_SYNC=${#OUTPUT_FILE_NAMES[@]}
SYNCED_FILES=()
i=0
while [ ${#SYNCED_FILES[@]} != $COUNT_TO_SYNC ] && [ $i -lt 30 ] ; do
  sleep 0.5
  for OUTPUT_FILE_NAME in "${OUTPUT_FILE_NAMES[@]}"; do
    if [[ " ${SYNCED_FILES[@]} " =~ " ${OUTPUT_FILE_NAMES} " ]]; then
      continue
    fi
    STATUS=$("$HOME/Dropbox/scripts/dropbox.py" filestatus "$OUTPUT_FILE_NAME" | grep -- "up to date")
    if [ "$STATUS" != "" ]; then
      SYNCED_FILES+=( "$OUTPUT_FILE_NAME" )
    fi
  done
  ((i=i+1))
done

if [ ${#SYNCED_FILES[@]} != $COUNT_TO_SYNC ]; then
  dunstify -t 5000 -u c "Couldn't Dropbox sync zathura file at $OUTPUT_FILE."
else
  dunstify -t 5000 "Dropbox synced zathura file at $OUTPUT_FILE."
fi
sleep 1
