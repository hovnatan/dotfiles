#!/bin/bash

PIDS=$(ps aux | head -n -2 | grep "zathura -e" | awk '{print $2}')
if [[ "$PIDS" == "" ]] ; then
  echo "Nothing to save"
  exit 0
fi

OUTPUT_FILE="$1"
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
