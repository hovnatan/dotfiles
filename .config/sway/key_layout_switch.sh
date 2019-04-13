#!/usr/bin/bash
LNG=$(xkblayout-state print %s)
case $LNG in
  "en_US")
    swaymsg input '*' xkb_layout am
    swaymsg input '*' xkb_variant "phonetic-alt"
    ;;
  "am")
    swaymsg input '*' xkb_layout us
    swaymsg input '*' xkb_variant "euro"
    ;;
esac
