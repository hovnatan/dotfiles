#!/bin/bash

num=$(ssh -Y $1 'tmux list-sessions' | grep -v attached | wc -l)

for i in `seq 1 $num`;
do
  nohup termite -e "ssh -t -Y $1 tmux_attach_deattached.sh" >/dev/null 2>&1 &
done
