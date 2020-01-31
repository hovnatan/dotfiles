#!/bin/bash

COMMAND=$1
NAME=$2

while true; do
  i3-msg "[instance=\"$2\"] scratchpad show, resize set 1280 720, move position center"
  if [ $? == 0 ]; then
    break
  fi
  i3-msg "exec --no-startup-id termite --name \"$NAME\" -e \"$COMMAND\""
  sleep 0.5
done
