#!/bin/bash

if [ "$TMUX_ONE_WINDOW" == "1" ]; then
  tmux source-file "$HOME/.dotfiles/tmux_one_window.conf"
fi
