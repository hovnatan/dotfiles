#!/bin/bash

if [ -z $1 ]; then
  session=$(tmux list-sessions | grep -v attached | head -n 1 | sed -rn 's/^([0-9]+):.*/\1/p')
else
  session=$1
fi

if [ -z $session ] ; then
  tmux
else
  tmux a -t $session
fi
