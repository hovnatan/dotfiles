#!/bin/sh

n=$(i3-msg -t get_workspaces \
  | jq '.[] | select(.focused==true).name' \
  | cut -d"\"" -f2)
if [ $n = "10" ]; then
  i3-msg "focus right"
else
  i3-msg "workspace 10"
fi
