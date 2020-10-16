#!/bin/bash

dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.GetOperationMode | grep normal
if [[ "$?" != 0 ]]; then
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:normal
  notify-send -i /usr/share/icons/hicolor/scalable/apps/workrave.svg -t 1000 "Workrave" "Turned on."
  pkill -f -9 "bash.*workrave_toggle.sh"
else
  INDEX=$(echo "5 minutes|15 minutes|30 minutes|1 hour|2 hours" | rofi -font "mono 14" -width -75 -sep '|' -dmenu -p "Suspend Workrave for > " -format i)
  TIME=900
  case $INDEX in
    0)
      TIME=300
      ;;
    1)
      TIME=900
      ;;
    2)
      TIME=1800
      ;;
    3)
      TIME=3600
      ;;
    4)
      TIME=7200
      ;;
    *)
      notify-send -t 1000 "No choice."
      exit 1
  esac
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:quiet
  notify-send -i /usr/share/icons/hicolor/scalable/apps/workrave.svg -t 1000 "Workrave" "Turned off for $TIME seconds."
  SOON=$(($(date +%s) + $TIME))
  while [[ "$NOW" -le "$SOON" ]]; do
      sleep 30
      NOW=$(date +%s)
  done
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:normal
  notify-send -i /usr/share/icons/hicolor/scalable/apps/workrave.svg -t 1000 "Workrave" "Turned on."
fi

