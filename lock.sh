#!/bin/bash

if ! pgrep -x "i3lock" > /dev/null ;
then
  eval $(xdotool getmouselocation --shell)
  echo "$X"
  if [ "$X" -gt 30 ] ; then  
    nohup ~/.dotfiles/.config/i3/lock.sh >/dev/null 2>&1 &
    setxkbmap us
    if ! [ -z "$1" ] ; 
    then 
      # Turn the screen off after a delay.
      sleep 3
      if pgrep -x "i3lock" > /dev/null
      then
        xinput --disable "$POINTER_DEVICE_ID_TO_SUSPEND"
        xset dpms force off
      fi
    fi
  fi
fi
