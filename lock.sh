#!/bin/bash
if ! pgrep -x "i3lock" > /dev/null ;
then
  # Take a screenshot
  scrot /tmp/screen_locked.png

  # Pixellate it 5x
  mogrify -scale 5% -scale 2000% /tmp/screen_locked.png

  # Lock screen displaying this image.
  i3lock -i /tmp/screen_locked.png

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
