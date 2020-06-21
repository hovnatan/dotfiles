#!/bin/bash

xrdb -load ~/.Xresources

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
      [ -x "$f" ] && . "$f"
    done
unset f

# start_workrave.sh &
dunst &

exec i3
