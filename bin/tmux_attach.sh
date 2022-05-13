#!/bin/bash

if [ -z $1 ]; then
  session=$(tmux list-sessions | head -n 1 | cut -d: -f1)
  if [ -z $session ]; then
    session="default"
  fi
else
  session=$1
fi

tmux new-session -As ${session}
