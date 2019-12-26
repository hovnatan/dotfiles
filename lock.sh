#!/bin/bash

if ! pgrep -x "i3lock" > /dev/null ;
then
  eval $(xdotool getmouselocation --shell)
  if [ "$X" -gt 30 ] || [ "$1" != "autolock" ] ; then
    nohup ~/.dotfiles/.config/i3/lock.sh >/dev/null 2>&1 &
    xkb-switch -s us
    zathura_save.sh
    if [ "$1" != "sleep" ] ;
    then
      # Turn the screen off after a delay.
      sleep 3
      if pgrep -x "i3lock" > /dev/null
      then
        xinput --disable $(xinput --list | sed -rn 's/.*Mouse.*Mouse.*id=([0-9]+).*/\1/p')
        xset dpms force off
      fi
    fi
  fi
fi
