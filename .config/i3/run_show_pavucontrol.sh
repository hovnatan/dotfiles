#!/bin/bash


if ! pgrep -x "pavucontrol" ; then
  dex /usr/share/applications/pavucontrol.desktop
fi
while true; do
  i3-msg "[class=\"Pavucontrol\"] scratchpad show, resize set 1280 720, move position center"
  if [[ $? == 0 ]]; then
    break
  fi
done
