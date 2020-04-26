#!/bin/bash

INDEX=$(echo "15 minutes|30 minutes|1 hour|2 hours" | rofi -width -75 -sep '|' -dmenu -p "Suspend notifications for > " -format i)
case $INDEX in
  0)
    TIME=900
    ;;
  1)
    TIME=1800
    ;;
  2)
    TIME=3600
    ;;
  3)
    TIME=7200
    ;;
  *)
    dunstify -t 1000 "No choice."
    exit 1
esac

LOCK_FILE="$HOME/tmp/dunst_paused.file"

if [[ -f "$LOCK_FILE" ]] ; then
  PID=$(cat "$LOCK_FILE")
  kill -9 $PID
fi
echo $$ > "$LOCK_FILE"

dunstify -t 2000 "Turn off notifications for $TIME seconds."
sleep 1
killall -SIGUSR1 dunst

SOON=$(($(date +%s) + $TIME))
while [[ "$NOW" -le "$SOON" ]]; do
    sleep 30
    NOW=$(date +%s)
done

killall -SIGUSR2 dunst
dunstify -t 2000 "Turn on notifications"
rm "$LOCK_FILE"
