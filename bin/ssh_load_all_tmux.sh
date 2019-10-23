#!/bin/bash

sessions=$(ssh -Y $1 'tmux list-sessions')

if [ -z $2 ]
then
  sessions=$(echo "$sessions" | grep -v attached)
  tmux_command="tmux a -t"
else
  tmux_command="tmux a -dt"
fi

sessions=$(echo "$sessions" | cut -d: -f1)

for session in $sessions;
do
  nohup termite -e "ssh -t -Y $1 $tmux_command $session" >/dev/null 2>&1 &
  sleep 0.5
done

i3-msg layout tabbed
