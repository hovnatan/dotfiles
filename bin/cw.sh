#!/bin/bash

if [ $# -eq 1 ]
then
  COLOR=$1
elif [ -n "$BACKGROUND_COLOR" ]
then
  COLOR=$BACKGROUND_COLOR
else
  # currenttime=$(date +%H:%M)
  # if [[ "$currenttime" > "19:00" ]] || [[ "$currenttime" < "07:30" ]]; then
  MACOS_MODE=$(osascript -e 'tell app "System Events" to tell appearance preferences to get dark mode')
  if [ $MACOS_MODE == "true" ]; then
    COLOR="dark"
  else
    COLOR="light"
  fi
fi

echo -n "$COLOR" > ~/.my_colors

echo -n "set -U _reload_color_config ""$COLOR" | fish

# kitty @ --to $HOME/.tmpkitty set-colors -a -c ~/.config/kitty/base16-gruvbox-dark-medium.conf
color_switcher.sh ~/.config/alacritty/alacritty.yml ~/.config/alacritty/option ~/.config/alacritty/colors/$COLOR reverse

WINDOWS_HOME=$(wslpath "$(wslvar USERPROFILE)")
cp ~/.config/alacritty/alacritty.yml "$WINDOWS_HOME/AppData/Roaming/alacritty/alacritty.yml"
tmux source ~/.tmux.conf

color_switcher.sh ~/.config/bat/config ~/.config/bat/option ~/.config/bat/config_$COLOR

SIOYEK="$HOME/.dotfiles/.config/sioyek/"
color_switcher.sh "$SIOYEK/prefs_user.config" "$SIOYEK/prefs_user_common" "$SIOYEK/$COLOR" reverse

if [ $COLOR == "dark" ]
then
  sed -i '' 's/gruvbox-light/gruvbox-dark/g' ~/.gitconfig
else
  sed -i '' 's/gruvbox-dark/gruvbox-light/g' ~/.gitconfig
fi
