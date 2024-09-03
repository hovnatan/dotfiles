#!/usr/bin/env bash

if [ $# -eq 0 ]; then
  firejail --noprofile --net=none -- ~/sioyek/build/sioyek
else
  firejail --noprofile --net=none -- ~/sioyek/build/sioyek "$1"
fi
