#!/bin/sh

options='-width 100'

selected=$(\
        cat ~/.local/share/zathura/history | grep -Po '\[\K[^\]]*' \
        | rofi -dmenu -i -markup-rows \
        ${options}
        )

# exit if nothing is selected
[[ -z $selected ]] && exit

zathura "$selected"

exit 0
