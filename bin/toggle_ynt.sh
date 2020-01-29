#!/bin/bash

python $HOME/.dotfiles/bin/toggle_ynt.py
sleep 5
killall dunst
dunst &
