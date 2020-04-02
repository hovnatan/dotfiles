#!/bin/bash


while read LINE
do
  pactl set-sink-mute "$LINE" 1
done <<< $(pactl list short sinks | sed -e 's,^\([0-9][0-9]*\)[^0-9].*,\1,')

