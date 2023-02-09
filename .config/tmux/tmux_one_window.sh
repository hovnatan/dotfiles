#!/bin/bash

if [ "$TMUX_ONE_WINDOW" == "1" ]; then
  COLOR=$(cat ~/.my_colors)
  if [[ $COLOR == "light" ]] ; then
    tmux source-file "$HOME/.dotfiles/.config/tmux/tmux_light.conf"
  else
    tmux source-file "$HOME/.dotfiles/.config/tmux/tmux_dark.conf"
  fi
  tmux source-file "$HOME/.dotfiles/.config/tmux/tmux_one_window.conf"
fi
