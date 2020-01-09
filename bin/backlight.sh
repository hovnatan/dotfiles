#!/bin/bash

VAL=10

if [ "$1" == "up" ]; then
  xbacklight -inc $VAL
else
  xbacklight -dec $VAL
fi

get_progress_bar() {
    local percent="$1"
    local max_percent=${2:-100}
    local divisor=${3:-5}
    local progress=$((("$percent" > $max_percent ? $max_percent : $percent) / $divisor))

    printf '█%.0s' $(eval echo "{1..$progress}")
}

printf -v CURRENT_VAL %.0f $(xbacklight -get)

TEXT="Brightness $CURRENT_VAL% "
PROGRESS=$(get_progress_bar "$CURRENT_VAL")
TEXT="$TEXT $PROGRESS"

dunstify -t 1000 -r 1001 -h int:value:"$CURRENT_VAL" "$TEXT"
