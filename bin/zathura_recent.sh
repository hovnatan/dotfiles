#!/bin/sh

options='-width 90'

selected=$(\
        cat ~/.local/share/zathura/history | grep -Po '\[\K[^\]]*' \
        | sed "s|^$HOME|~|" \
        | rofi -dmenu -i \
        ${options}
        )

# exit if nothing is selected
[[ -z $selected ]] && exit

zathura "$selected"

exit 0
