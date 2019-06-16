#!/bin/bash

COLOR=$1
echo -n "$COLOR" > ~/.my_colors

xrdb -override ~/.dotfiles/.Xresources_grb_"$COLOR"

color_switcher.sh ~/.config/termite/config ~/.config/termite/option ~/.config/termite/colors/$COLOR
killall -USR1 termite
echo -n "set -U _reload_color_config ""$COLOR" | fish

color_switcher.sh ~/.config/zathura/zathurarc ~/.config/zathura/option ~/.config/zathura/colors/$COLOR

color_switcher.sh ~/.dotfiles/.config/gtk-3.0/settings.ini ~/.dotfiles/.config/gtk-3.0/settings_option ~/.dotfiles/.config/gtk-3.0/colors/$COLOR

color_switcher.sh ~/.config/rofi/config ~/.config/rofi/option ~/.config/rofi/colors/$COLOR

color_switcher.sh ~/.dotfiles/.config/dunst/dunstrc ~/.dotfiles/.config/dunst/option ~/.dotfiles/.config/dunst/colors/$COLOR
killall dunst

i3-msg reload
