#!/bin/bash

EXTERNAL_OUTPUT="$EXTERNAL_MONITOR_OUTPUT"
INTERNAL_OUTPUT="$INTERNAL_MONITOR_OUTPUT"

DATA_FILE="${HOME}/.local/monitor_mode.dat"
if [ ! -f "$DATA_FILE" ] ; then
  monitor_mode="all"
else
  monitor_mode=`cat "$DATA_FILE"`
fi

if [ -z "$1" ] ;
then
  if [ $monitor_mode = "all" ]; then
    monitor_mode="EXTERNAL"
  elif [ $monitor_mode = "EXTERNAL" ]; then
    monitor_mode="INTERNAL"
  else
    monitor_mode="all"
  fi
fi

if [ $monitor_mode = "all" ]; then
  xrandr --output $INTERNAL_OUTPUT --auto --output $EXTERNAL_OUTPUT --auto $EXTERNAL_MONITOR_LOCATION $INTERNAL_OUTPUT
elif [ $monitor_mode = "EXTERNAL" ]; then
  xrandr --output $INTERNAL_OUTPUT --off --output $EXTERNAL_OUTPUT --auto
else
  xrandr --output $INTERNAL_OUTPUT --auto --output $EXTERNAL_OUTPUT --off
fi

echo "${monitor_mode}" > "$DATA_FILE"
${HOME}/.dotfiles/xautolock_start.sh &

setkmap.sh us
