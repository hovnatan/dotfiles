#!/usr/bin/env bash
# Depends on: xdotool, wmctrl

FOCUSED=$(wmctrl -lp | grep $(xprop -root | grep _NET_ACTIVE_WINDOW | head -1 | awk '{print $5}' | sed 's/,//' | sed 's/^0x/0x0/'))
FPID=$(echo $FOCUSED | awk '{print $3}')
FNME=$(echo $FOCUSED | cut -f -4  -d ' ' --complement)
if [ "$1" == "" ]; then
  NEW_NAME=$(echo "$FNME" | rofi -sep '|' -dmenu -p "New name > ")
  if [ "$NEW_NAME" == "" ]; then
    exit 1
  fi
else
  NEW_NAME="$1"
fi
FNME=${FNME//(/"\("}
FNME=${FNME//)/"\)"}
xdotool search -all --pid $FPID --name "$FNME" set_window -name "$NEW_NAME"
