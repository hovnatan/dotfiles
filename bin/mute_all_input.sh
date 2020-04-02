#!/bin/bash

while read LINE
do
  pactl set-source-mute "$LINE" 1
done <<< $(pactl list short sources | sed -e 's,^\([0-9][0-9]*\)[^0-9].*,\1,')
