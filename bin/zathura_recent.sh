#!/bin/sh

options='-width -130'

pdfs=$(cat ~/.local/share/zathura/history | grep -Po '\[\K[^\]]*')
index=$(echo "$pdfs" \
        | sed "s|^$HOME|~|" \
        | grep -o -P '.{0,125}$' \
        | rofi -dmenu -i -p 'zathura history' -format i \
        ${options}
        )

# exit if nothing is selected
[[ -z $index ]] && exit

((++index))
selected=$(echo "$pdfs" | sed -n "$index"p)

zathura "$selected"

exit 0