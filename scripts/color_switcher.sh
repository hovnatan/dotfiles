#!/bin/bash

CONFIG="$1"
OPTION="$2"
COLOR_PATH="$3"
if [[ "$4" == "" ]]; then
  cat "$COLOR_PATH" > "$CONFIG"
  echo >> "$CONFIG"
  cat "$OPTION" >> "$CONFIG"
else
  cat "$OPTION" > "$CONFIG"
  echo >> "$CONFIG"
  cat "$COLOR_PATH" >> "$CONFIG"
fi
