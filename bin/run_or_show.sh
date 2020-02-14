#!/bin/bash

i3-msg "[instance=\"$1\"] focus"
if [[ $? != 0 ]]; then
  eval $2
  while true; do
    sleep 0.5
    i3-msg "[instance=\"$1\"] focus"
    if [[ $? == 0 ]]; then
      break
    fi
  done
fi
