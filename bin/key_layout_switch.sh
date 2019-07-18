#!/bin/bash

LNG=$(check_layout.sh)
case $LNG in
  "am")
    setkmap.sh us ;;
  "us")
    setkmap.sh am ;;
esac
