#!/bin/bash

FMT='{{playerName}}
{{artist}} - {{title}}
{{duration(position)}} | {{duration(mpris:length)}}'

INFO=$(playerctl metadata --format "${FMT}")

IFS=$'\n'
INFO=($INFO)
dunstify -t 5000 "Playing from ${INFO[0]}" "${INFO[1]}\n${INFO[2]}"
