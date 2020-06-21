#!/bin/bash

xrdb -load ~/.Xresources

# start_workrave.sh &
dunst &

exec i3
