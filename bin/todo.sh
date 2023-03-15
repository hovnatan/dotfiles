#!/usr/bin/env bash

if [ $# -eq 0 ]; then
  nvim "$HOME/Dropbox/container_in_out/todo/todo.md"
else
  nvim "$HOME/Dropbox/container_in_out/todo/todo_$1.md"
fi
