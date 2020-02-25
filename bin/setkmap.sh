#!/bin/bash

setxkbmap -option ""
setxkbmap -layout "us,am" -variant ",phonetic-alt"
xkbcomp $HOME/.dotfiles/.config/xkb/config $DISPLAY

sleep 5

xcape -e "Control_L=Escape"
