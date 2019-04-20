#!/usr/bin/bash

LNG=$(check_layout.sh)

case $LNG in
  "us")
    swaymsg input '*' xkb_layout "am,us"
    swaymsg input '*' xkb_variant "phonetic-alt,"
    ;;
  "am")
    swaymsg input '*' xkb_layout "us,am"
    swaymsg input '*' xkb_variant ",phonetic-alt"
    ;;
esac
