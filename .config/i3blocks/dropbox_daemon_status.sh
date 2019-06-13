#!/usr/bin/env bash

case $BLOCK_BUTTON in
    1) dropbox_daemon.py ;;
    3) pkill -f dropbox_daemon.py ;;
esac

STATUS=$(pgrep -f dropbox_daemon.py)

if [ -z "$STATUS" ]; then
  CLR=\#af3a03
else
  CLR=\#79740e 
fi

echo "dbox"
echo "dbox"
echo "$CLR"
