#!/bin/bash

wa=$(i3-msg -t get_workspaces \
  | jq '.[] | select(.focused==true).name' \
  | cut -d"\"" -f2)

dunstify -t 2000 "$wa"
i3-msg workspace $1
