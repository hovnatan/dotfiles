#!/bin/bash

if [ $# -eq 1 ]
then
  COLOR=$1
elif [ -n "$BACKGROUND_COLOR" ]
then
  COLOR=$BACKGROUND_COLOR
else
  currenttime=$(date +%H:%M)
  if [[ "$currenttime" > "19:00" ]] || [[ "$currenttime" < "07:30" ]]; then
    COLOR="dark"
  else
    COLOR="light"
  fi
fi

echo -n "$COLOR" > ~/.my_colors

<<<<<<< HEAD
xrdb -override ~/.dotfiles/.Xresources_grb_"$COLOR"

color_switcher.sh ~/.config/alacritty/alacritty.yml ~/.config/alacritty/option ~/.config/alacritty/colors/$COLOR reverse
color_switcher.sh ~/.config/kitty/kitty.conf ~/.config/kitty/option ~/.config/kitty/colors/$COLOR
color_switcher.sh ~/.config/termite/config ~/.config/termite/option ~/.config/termite/colors/$COLOR
killall -USR1 termite
=======
>>>>>>> cleanup
echo -n "set -U _reload_color_config ""$COLOR" | fish
