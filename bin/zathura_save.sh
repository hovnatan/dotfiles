#!/bin/bash

OUTPUT_FILE="$HOME/Dropbox/scripts/zathura/zathura_save"
mv "$OUTPUT_FILE" "$OUTPUT_FILE.bak"

PIDS=$(pidof zathura)
for PID in $PIDS; do
  filename=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:filename | grep -oP ".*variant.*string\s+\"\K(.*)(?=\")")
  pagenumber=$(dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura \
    org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:pagenumber | grep -oP ".*variant.*uint32\s+\K(.*)")
  echo "$filename:$pagenumber" >> "$OUTPUT_FILE"
done

SYNCED=""
while [ "$SYNCED" == "" ] ; do
  sleep 0.5
  SYNCED=$("$HOME/Dropbox/scripts/dropbox.py" filestatus "$OUTPUT_FILE" | grep -- "up to date")
done
