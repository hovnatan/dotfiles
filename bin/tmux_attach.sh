#!/bin/bash

if [ -z $1 ]; then 
  exit 1
fi

if ! tmux has-session -t "$1" 2>/dev/null; then
  tmux new-session -d -s "$1" -n nvim
  tmux new-window -n cmd1 -t "$1"
  tmux new-window -n r1 -t "$1"
fi
tmux attach-session -t "$1"
