#!/bin/bash

COMMAND=$1
NAME=$2

call_command() {
    i3-msg "exec --no-startup-id termite --name \"$NAME\" -e $COMMAND"
    sleep 0.2
}

while true; do
  if ! pgrep -x "$1" ; then
    call_command
  fi
  i3-msg "[instance=\"$2\"] scratchpad show, resize set 1280 720, move position center"
  if [ $? == 0 ]; then
    break
  fi
  call_command
done
