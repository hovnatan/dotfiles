#!/usr/bin/env bash

# Set the console color palette.

color() {
  echo -n "\e]P${1}${2}"
}

color 0  '1d2021'
color 1  'fb4934'
color 2  'b8bb26'
color 3  'fabd2f'
color 4  '83a598'
color 5  'd3869b'
color 6  '8ec07c'
color 7  'ebdbb2'
color 8  '928374'
color 9  'cc241d'
color a  '98971a'
color b  'd79921'
color c  '458588'
color d  'b16286'
color e  '689d6a'
color f  'a89984'

clear
