#!/bin/bash

setxkbmap -option ""
setxkbmap -layout "us,am" -variant ",phonetic-alt" -option "grp:alt_space_toggle,ctrl:nocaps,grp:rctrl_switch"
# xkbcomp $HOME/.dotfiles/.config/xkb/config $DISPLAY

pkill -9 xcape
xcape -e "Control_L=Escape"
