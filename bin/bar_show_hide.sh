#!/bin/bash

i3-msg bar hidden_state show
sleep 0.2
if [[ "$1" != "" ]]; then
  xdotool key "$1"
fi
sleep 1
i3-msg bar hidden_state hide
