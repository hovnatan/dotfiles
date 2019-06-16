#!/bin/sh

xrdb -load ~/.Xresources
light_dark=$(cat ~/.my_colors)

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f

cw.sh $light_dark
exec i3
#exec i3 --shmlog-size=26214400
