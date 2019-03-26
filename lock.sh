#!/bin/bash
if ! pgrep -x "i3lock" > /dev/null ;
then
  eval $(xdotool getmouselocation --shell)
  echo "$X"
  if [ "$X" -gt 30 ] || [ "$Y" -gt 30 ] ; then  
    ~/.dotfiles/.config/i3/lock.sh
    setxkbmap us
    if ! [ -z "$1" ] ; 
    then 
      # Turn the screen off after a delay.
      sleep 30
      if pgrep -x "i3lock" > /dev/null
      then
        xset dpms force off
      fi
    fi
  fi
fi
