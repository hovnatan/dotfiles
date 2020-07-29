#!/bin/bash

INPUT_DIR="$HOME/Dropbox/scripts/zathura/saves"
if [[ "$1" == "" || "$1" == "load_from_rofi" ]]; then
  FILES=""
  FILEPATHS=()
  FILENAMES=$()

  while IFS= read -r FILENAME
  do
    FILEPATH="$INPUT_DIR/$FILENAME"
    FILEPATHS+=( "$FILEPATH" )
    MOD_TIME=$(date -r "$FILEPATH" "+%m/%d/%Y %H:%M:%S")
    printf -v TEXT "%-35s%37s" "$FILENAME" "$MOD_TIME"
    FILES="$FILES|$TEXT"
  done <<< $(/usr/bin/ls -1t --color=no "$INPUT_DIR")

  FILES="${FILES:1}"
  INDEX=$(echo "$FILES" | rofi -width -75 -sep '|' -dmenu -p "Load filename > " -format i)
  if [[ $INDEX != "" ]]; then
    INPUT_FILE=${FILEPATHS[$INDEX]}
  fi
else
  INPUT_FILE="$1"
fi

if [ ! -f "$INPUT_FILE" ]; then
  dunstify -t 5000 "Wrong filename $INPUT_FILE."
  exit 1
fi

i3-msg layout tabbed

IFS=:
cat "$INPUT_FILE" | while read line
do
  read filename pagenumber workspace name <<< "$line"
  pagenumber="${pagenumber#"${pagenumber%%[!0]*}"}" # remove leading zeros
  if [ "$pagenumber" == "" ]; then
    pagenumber=0
  fi
  ((++pagenumber))
  zathura -P "$pagenumber" "$filename" &
  PID="$!"
  while true; do
    sleep 0.1
    if dbus-send --print-reply --type=method_call --dest=org.pwmt.zathura.PID-$PID /org/pwmt/zathura org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:pagenumber ; then
      break
    fi
  done
  $HOME/.dotfiles/bin/set_w_name.sh "$name"
done
