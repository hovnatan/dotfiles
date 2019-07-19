#!/bin/bash

 # setxkbmap -layout "us,am" -variant ",phonetic-alt" -option "ctrl:nocaps,grp:rctrl_switch"
setxkbmap -option ""
if [ $1 = "us" ]; then
   setxkbmap -layout "us,am" -variant ",phonetic-alt" -option "ctrl:nocaps,grp:rctrl_switch"
 else
   setxkbmap -layout "am,us" -variant "phonetic-alt," -option "ctrl:nocaps,grp:rctrl_switch"
 fi
