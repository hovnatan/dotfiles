#!/bin/bash

session=$(tmux list-sessions | grep -v attached | sed -rn 's/^([0-9]+):.*/\1/p')
if [ -z $session ] ; then
  tmux
else
  tmux a -t $session
fi
