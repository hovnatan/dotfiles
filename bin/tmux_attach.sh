#!/bin/bash

if [ -z $1 ]; then
  session="default"
else
  session=$1
fi

tmux new-session -As ${session}
