#!/bin/sh

# initialize X resource database (if file ~/.Xresources is present on the system)
xrdb -load ~/.Xresources

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f

exec i3
#exec i3 --shmlog-size=26214400
