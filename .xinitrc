#!/bin/bash

xrdb -load ~/.Xresources

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
      [ -x "$f" ] && . "$f"
    done
unset f

# start_workrave.sh &
# dunst &

# exec i3

export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
exec gnome-session
