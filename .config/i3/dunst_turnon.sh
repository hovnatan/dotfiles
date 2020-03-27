#!/bin/bash

LOCK_FILE="$HOME/tmp/dunst_paused.file"

if [[ -f "$LOCK_FILE" ]] ; then
  PID=$(cat "$LOCK_FILE")
  kill -9 $PID
  rm "$LOCK_FILE"
fi

killall -SIGUSR2 dunst
dunstify -t 2000 "Turn on notifications"
