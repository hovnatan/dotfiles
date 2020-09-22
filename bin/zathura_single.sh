#!/bin/bash

XID_TABBED=$(cat "$HOME/.tabbed.xid")

if [[ "$XID_TABBED" == "" ]]; then
  XID_TABBED=$(tabbed -d)
  wmctrl -i -r $XID_TABBED -b add,maximized_vert,maximized_horz
  echo "Tabbed XID $XID_TABBED"
  echo "$XID_TABBED" > ~/.tabbed.xid
fi

zathura -e $XID_TABBED "$1" &
