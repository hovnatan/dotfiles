#!/bin/sh

xrdb -load ~/.Xresources
cw.sh

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f

~/Dropbox/scripts/dropbox.py start &
redshift-gtk &
libinput-gestures &
nm-applet --sm-disable &
blueman-applet &
#exec i3
#exec i3 --shmlog-size=26214400
exec awesome
