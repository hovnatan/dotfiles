#!/bin/bash

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac

if [ $# -eq 1 ]
then
  COLOR=$1
elif [ -n "$BACKGROUND_COLOR" ]
then
  COLOR=$BACKGROUND_COLOR
else
  if [ "$machine" == "Linux" ]; then 
    currenttime=$(date +%H:%M)
    if [[ "$currenttime" > "19:00" ]] || [[ "$currenttime" < "07:30" ]]; then
      COLOR="dark"
    else
      COLOR="light"
    fi
  elif [ "$machine" == "Mac" ];  then
    MACOS_MODE=$(osascript -e 'tell app "System Events" to tell appearance preferences to get dark mode')
    if [ "$MACOS_MODE" == "true" ]; then
      COLOR="dark"
    else
      COLOR="light"
    fi
  fi
fi

echo -n "$COLOR" > ~/.my_colors

echo -n "set -U _reload_color_config ""$COLOR" | fish

# kitty @ --to $HOME/.tmpkitty set-colors -a -c ~/.config/kitty/base16-gruvbox-dark-medium.conf
color_switcher.sh ~/.config/alacritty/alacritty.yml ~/.config/alacritty/option ~/.config/alacritty/colors/$COLOR reverse

if [[ "$WSL_DISTRO_NAME" ]]; then
  WINDOWS_HOME=$(wslpath "$(wslvar USERPROFILE)")
  cp ~/.config/alacritty/alacritty.yml "$WINDOWS_HOME/AppData/Roaming/alacritty/alacritty.yml"
fi

tmux source ~/.config/tmux/tmux.conf

color_switcher.sh ~/.config/bat/config ~/.config/bat/option ~/.config/bat/config_$COLOR

SIOYEK="$HOME/.dotfiles/.config/sioyek/"
color_switcher.sh "$SIOYEK/prefs_user.config" "$SIOYEK/prefs_user_common" "$SIOYEK/$COLOR" reverse

if [ $COLOR == "dark" ]; then
  if [ "$machine" == "Linux" ]; then
    sed -i 's/gruvbox-light/gruvbox-dark/g' ~/.gitconfig
  else # Mac
    sed -i '' 's/gruvbox-light/gruvbox-dark/g' ~/.gitconfig
  fi
else
  if [ "$machine" == "Linux" ]; then
    sed -i 's/gruvbox-dark/gruvbox-light/g' ~/.gitconfig
  else # Mac
    sed -i '' 's/gruvbox-dark/gruvbox-light/g' ~/.gitconfig
  fi
fi
