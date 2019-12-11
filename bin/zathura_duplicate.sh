#!/bin/bash

ID=$(xdpyinfo | grep focus | cut -f4 -d " ")

# Get PID of process whose window this is
PID=$(xprop -id $ID | grep -m 1 PID | cut -d " " -f 3)

# Get last child process (shell, vim, etc)
if [ -n "$PID" ]; then
  Z_CMD=$(ps -f --pid $PID | grep -Po 'zathura \K.*')
  zathura "$Z_CMD"
fi
