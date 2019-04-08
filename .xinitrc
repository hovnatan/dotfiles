#!/bin/sh

xrdb -load ~/.Xresources
xrdb -override ~/.dotfiles/.Xresources_nord

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f

exec i3
#exec i3 --shmlog-size=26214400
