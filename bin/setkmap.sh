#!/bin/bash

setxkbmap -option ""
setxkbmap -layout "us,am" -variant ",phonetic-alt" -option "ctrl:nocaps,grp:rctrl_switch"

sleep 5

xcape -e "Control_L=Escape"
