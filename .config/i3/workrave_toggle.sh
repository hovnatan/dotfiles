#!/bin/bash

dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.GetOperationMode | grep normal
if [[ "$?" != 0 ]]; then
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:normal
  dunstify -i /usr/share/icons/hicolor/scalable/apps/workrave.svg -t 1000 "Workrave" "Turned on."
  pkill -f -9 "bash.*workrave_toggle.sh"
else
  INDEX=$(echo "15 minutes|30 minutes|1 hour|2 hours" | rofi -width -75 -sep '|' -dmenu -p "Suspend Workrave for > " -format i)
  TIME=900
  case $INDEX in
    0)
      TIME=900
      ;;
    1)
      TIME=1800
      ;;
    2)
      TIME=3600
      ;;
    3)
      TIME=7200
      ;;
    *)
      dunstify -t 1000 "No choice."
      exit 1
  esac
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:quiet
  dunstify -i /usr/share/icons/hicolor/scalable/apps/workrave.svg -t 1000 "Workrave" "Turned off for $TIME seconds."
  SOON=$(($(date +%s) + $TIME))
  while [[ "$NOW" -le "$SOON" ]]; do
      sleep 30
      NOW=$(date +%s)
  done
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:normal
  dunstify -i /usr/share/icons/hicolor/scalable/apps/workrave.svg -t 1000 "Workrave" "Turned on."
fi

