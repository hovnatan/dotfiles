#!/bin/bash

PIDS=$(wmctrl -lp | awk '{print $3}')

OUTPUT_DIR="$HOME/Dropbox/scripts/zathura/saves"
OUTPUT_FILE="$1"
OUTPUT_FILE="${OUTPUT_FILE}_$(hostname)"
OUTPUT_FILE="$OUTPUT_DIR/$OUTPUT_FILE"
rm "$OUTPUT_FILE"

while read PID
do
  ps -p $PID | grep zathura
  if [[ $? != 0 ]] ; then
    continue
  fi
  filename=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:filename | grep -oP ".*variant.*string\s+\"\K(.*)(?=\")")
  pagenumber=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:pagenumber | grep -oP ".*variant.*uint32\s+\K(.*)")
  printf -v OUTPUT_PAGENUMBER "%05d" $pagenumber
  echo "$filename:$OUTPUT_PAGENUMBER" >> "$OUTPUT_FILE"
done <<< "$PIDS"

sort -o "$OUTPUT_FILE" "$OUTPUT_FILE"
