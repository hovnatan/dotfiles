#!/bin/bash

LNG=$(check_layout.sh)
case $LNG in
  "am")
    setxkbmap -layout "us,am" -variant ",phonetic-alt" -option "" ;;
  "us")
    setxkbmap -layout "am,us" -variant "phonetic-alt," -option "" ;;
esac
setxkbmap -option "ctrl:nocaps,grp:rctrl_switch"
