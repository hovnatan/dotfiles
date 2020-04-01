#!/bin/bash

BLOCK_INSTANCE=battery_BAT0

INFO=$(upower -i "/org/freedesktop/UPower/devices/${BLOCK_INSTANCE}")
STATE=$(echo "$INFO" | grep 'state:'  | awk '{ print $2 }' | awk '{ print toupper($0) }')
PERCENTAGE=$(echo "$INFO" | grep 'percentage:'  | awk '{ print $2 }')
DRAIN=$(echo "$INFO" | grep 'energy-rate:'  | awk '{ print $2 }')
printf '%s %.0f%% %.1fW\n' ${STATE:0:3} ${PERCENTAGE%\%} ${DRAIN}
