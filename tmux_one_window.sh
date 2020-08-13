#!/bin/bash

if [ "$TMUX_ONE_WINDOW" == "1" ]; then
  COLOR=$(cat ~/.my_colors)
  if [[ $COLOR == "light" ]] ; then
    tmux source-file "$HOME/.dotfiles/tmux_light.conf"
  else
    tmux source-file "$HOME/.dotfiles/tmux_dark.conf"
  fi
  tmux source-file "$HOME/.dotfiles/tmux_one_window.conf"
fi
