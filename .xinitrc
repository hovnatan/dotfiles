#!/bin/sh

xrdb -load ~/.Xresources
xrdb -override ~/.dotfiles/.Xresources_grb_$(cat ~/.my_colors)

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f

exec i3
#exec i3 --shmlog-size=26214400
