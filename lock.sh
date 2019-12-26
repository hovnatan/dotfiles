#!/bin/bash

if ! pgrep -x "i3lock" > /dev/null ;
then
  eval $(xdotool getmouselocation --shell)
  if [ "$X" -gt 30 ] || [ "$1" != "autolock" ] ; then
    ~/.dotfiles/.config/i3/lock.sh &
    xkb-switch -s us
    zathura_save.sh
    if [ "$1" != "sleep" ] ;
    then
      # Turn the screen off after a delay.
      sleep 3
      if pgrep -x "i3lock" > /dev/null
      then
        xset dpms force off
      fi
    fi
  fi
fi
