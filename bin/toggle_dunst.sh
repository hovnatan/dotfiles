#!/bin/bash

LOCK_FILE="$HOME/tmp/$USER-dunst-lock.file"

if [[ -f "$LOCK_FILE" ]] ; then
  dunstify DUNST_COMMAND_RESUME
  dunstify -t 1000 "Notifications on"
  rm "$LOCK_FILE"
else
  dunstify -t 1000 "Notifications off"
  sleep 1
  dunstify DUNST_COMMAND_PAUSE
  echo $$ > "$LOCK_FILE"
fi
