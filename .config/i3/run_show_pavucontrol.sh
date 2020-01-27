#!/bin/bash


if ! pgrep -x "pavucontrol" ; then
  dex /usr/share/applications/pavucontrol.desktop
  sleep 0.2
fi
i3-msg "[class=\"Pavucontrol\"] scratchpad show, resize set 1280 720, move position center"
