#!/bin/bash

if [ $# -eq 0 ]; then
  firejail --noprofile --net=none -- ~/Downloads/Sioyek-x86_64.AppImage
else
  firejail --noprofile --net=none -- ~/Downloads/Sioyek-x86_64.AppImage "$1"
fi



