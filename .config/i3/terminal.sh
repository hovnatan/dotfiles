#!/bin/bash

# i3 thread: https://faq.i3wm.org/question/150/how-to-launch-a-terminal-from-here/?answer=152#post-id-152
# Inspired by https://gist.github.com/viking/5851049 but with support for tmux

CWD=''
CMD_L="tmux new-session"

# Get window ID
ID=$(xdpyinfo | grep focus | cut -f4 -d " ")

# Get PID of process whose window this is
PID=$(xprop -id $ID | grep -m 1 PID | cut -d " " -f 3)

# Get last child process (shell, vim, etc)
if [ -n "$PID" ]; then
	TREE=$(pstree -lpA $PID)
  SSH_PID=$(echo $TREE | grep -oP "(?<=ssh\()[0-9]+(?=\))")
	if [ ! -z "$SSH_PID" ];
  then
    SSH_ARGS=$(pstree -a $SSH_PID)
    CMD_L=$(echo $SSH_ARGS | grep -oP ".*([0-9]{1,3}\.){3}[0-9]{1,3} (tmux)?")
  else
    # chaning to current dir
    TMUX_PID=$(echo $TREE | grep -oP "(?<=tmux: client\()[0-9]+(?=\))")
    if [ ! -z "$TMUX_PID" ];
    then
      # To get the pid of the actual process we:
      # - find the pts of the tmux process found above
      PTS=$(ps -ef | grep $TMUX_PID | grep -v grep | awk '{print $6}');
      # - find the tmux session that's attached to the pts
      TMUX_SESSION=$(tmux lsc -t /dev/${PTS} -F "#{client_session}")
      # - find the pane_pid of the session
      PID=$(tmux list-panes -st $TMUX_SESSION	-F '#{pane_pid}')
    else
      FISH_PID=$(echo $TREE | grep -oP "(?<=fish\()[0-9]+(?=\))")
      if [ ! -z "$FISH_PID" ]; then
        PID="$FISH_PID"
      else
        PID=$(echo $TREE | tail -n 1 | awk -F'---' '{print $NF}' | sed -re 's/[^0-9]//g')
      fi
    fi
    if [ -e "/proc/$PID/cwd" ]; then
      CWD=$(readlink /proc/$PID/cwd)
    fi
    cd "$CWD"
  fi
fi
#~/opt/xst/xst $@ -e tmux
#kitty $@ tmux
termite -e "$CMD_L $@" &
