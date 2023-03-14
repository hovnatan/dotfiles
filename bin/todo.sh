#!/usr/bin/env bash

if [ $# -eq 0 ]; then
  nvim "$HOME/Dropbox/container_in_out/todo/todo_list.txt"
else
  nvim "$HOME/Dropbox/container_in_out/todo/todo_list_$1.txt"
fi
