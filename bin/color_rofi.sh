#!/bin/bash

INDEX=$(echo "Auto|Light|Dark" | rofi -width -75 -sep '|' -dmenu -p "Colorscheme > " -format i)

case $INDEX in
  0)
    cw.sh
    ;;
  1)
    cw.sh light
    ;;
  2)
    cw.sh dark
    ;;
esac

