#!/bin/sh

xrdb -load ~/.Xresources
light_dark=$(cat ~/.my_colors)
xrdb -override ~/.dotfiles/.Xresources_grb_"$light_dark"

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f

color $light_dark
exec i3
#exec i3 --shmlog-size=26214400
