#!/bin/bash

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
  exit 1
fi

XID_TABBED=$(tabbed -d)

IFS=:
cat "$INPUT_FILE" | while read LINE
do
  read filename pagenumber <<< "$LINE"
  pagenumber="${pagenumber#"${pagenumber%%[!0]*}"}" # remove leading zeros
  if [ "$pagenumber" == "" ]; then
    pagenumber=0
  fi
  ((++pagenumber))
  zathura -e "$XID_TABBED" -P "$pagenumber" "$filename" &
  PID="$!"
  while true; do
    sleep 0.1
    if dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:pagenumber ; then
      break
    fi
  done
done
