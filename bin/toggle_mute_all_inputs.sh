#!/bin/bash

while read LINE
do
  pactl set-source-mute "$LINE" toggle
done <<< $(pactl list short sources | grep -v monitor | sed -e 's,^\([0-9][0-9]*\)[^0-9].*,\1,')
dunstify -t 2000 "Audio inputs toggled."
