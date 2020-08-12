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

color_switcher.sh ~/.config/zathura/zathurarc ~/.config/zathura/option ~/.config/zathura/colors/$COLOR
echo -n "set -U _reload_color_config ""$COLOR" | fish

# kitty @ --to $HOME/.tmpkitty set-colors -a -c ~/.config/kitty/base16-gruvbox-dark-medium.conf
color_switcher.sh ~/.config/alacritty/alacritty.yml ~/.config/alacritty/option ~/.config/alacritty/colors/$COLOR reverse
