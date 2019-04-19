#!/bin/bash

setxkbmap -query | grep "us,am" &> /dev/null
if [[ $? != 0 ]]; then echo -n "am"; else echo -n "us"; fi
