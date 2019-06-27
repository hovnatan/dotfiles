#!/bin/sh

xrdb -load ~/.Xresources
currenttime=$(date +%H:%M)
if [[ "$currenttime" > "19:00" ]] || [[ "$currenttime" < "06:30" ]]; then
  light_dark="dark"
else
  light_dark="light"
fi

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f


cw.sh $light_dark
exec i3
#exec i3 --shmlog-size=26214400
