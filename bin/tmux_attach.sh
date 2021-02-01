#!/bin/bash

if [ -z $1 ]; then
  session=$(tmux list-sessions | head -n 1 | cut -d: -f1)
else
  session=$1
fi

if [ -z $session ] ; then
  exec tmux
else
  exec tmux a -t $session
fi
