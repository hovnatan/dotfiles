#!/bin/bash

setxkbmap -query | grep "us,am" &> /dev/null
if [[ $? != 0 ]]; then echo "am"; else echo "us"; fi
