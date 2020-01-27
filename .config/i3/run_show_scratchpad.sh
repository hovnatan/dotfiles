#!/bin/bash

if ! pgrep -x "$1" ; then
    i3-msg "exec --no-startup-id termite --name $1-scrpad -e $1"
    sleep 0.2
fi
i3-msg "[instance=\"$1-scrpad\"] scratchpad show, resize set 1280 720, move position center"
