#!/bin/bash

COLOR=$1
echo -n "$COLOR" > ~/.my_colors

xrdb -override ~/.dotfiles/.Xresources_grb_"$COLOR"
i3-msg reload

color_switcher.sh ~/.config/termite/config ~/.config/termite/option ~/.config/termite/colors/$COLOR
killall -USR1 termite
echo -n "set -U _reload_color_config ""$COLOR" | fish

color_switcher.sh ~/.config/zathura/zathurarc ~/.config/zathura/option ~/.config/zathura/colors/$COLOR
