#!/usr/bin/env bash

if [ $# -eq 0 ]; then
  nvim "$HOME/Dropbox/container_in_out/todo/todo.txt"
else
  nvim "$HOME/Dropbox/container_in_out/todo/todo_$1.txt"
fi
