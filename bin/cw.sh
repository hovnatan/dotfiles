#!/bin/bash

COLOR=$1
echo -n "$COLOR" > ~/.my_colors

xrdb -override ~/.dotfiles/.Xresources_grb_"$COLOR"
i3-msg reload

color_switcher.sh ~/.config/termite/config ~/.config/termite/option ~/.config/termite/color/$COLOR

killall -USR1 termite
echo -n "set -U _reload_color_config ""$COLOR" | fish
