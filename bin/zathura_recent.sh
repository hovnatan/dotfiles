#!/bin/sh

PDFS=$(cat ~/.local/share/zathura/history | grep -Po '\[\K[^\]]*' | grep "pdf\|djvu")
N_PDFS=$(echo "$PDFS" | awk '{print NR  "> " $s}')
echo "$N_PDFS"

read INDEX
SELECTED=$(echo "$PDFS" | sed -n "$INDEX"p)
zathura "$SELECTED" &
