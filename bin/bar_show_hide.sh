#!/bin/bash

i3-msg bar hidden_state show
if [[ "$1" != "" ]]; then
  xdotool key "$1"
fi
sleep 0.7
i3-msg bar hidden_state hide
