#!/bin/sh

xrdb -load ~/.Xresources
cw.sh

for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
unset f

# pulseaudio --start --daemonize=yes
~/Dropbox/scripts/dropbox.py start &
redshift-gtk &
libinput-gestures &
nm-applet --sm-disable &
blueman-applet &
xss-lock -l -- ~/.dotfiles/lock-xss.sh &
unclutter --timeout 3 --jitter 3 -b &
udiskie --no-automount --tray &
dex /usr/share/applications/org.keepassxc.KeePassXC.desktop &
start_workrave.sh &
clipster -d &
xset s 300 &
xset -dpms &
dunst &

exec i3
#exec i3 --shmlog-size=26214400
#exec awesome
