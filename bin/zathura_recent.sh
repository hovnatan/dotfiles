#!/bin/sh

PDFS=$(cat ~/.local/share/zathura/history | grep -Po '\[\K[^\]]*' | grep -o -P '.{0,115}$')
echo "$PDFS"
read INDEX
((++INDEX))
SELECTED=$(echo "$PDFS" | sed -n "$INDEX"p)
zathura "$SELECTED" &
