#!/bin/bash

python $HOME/.dotfiles/bin/toggle_ynt.py
killall dunst
dunst &
