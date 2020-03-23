#!/bin/bash

dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.GetOperationMode | grep normal
if [[ "$?" != 0 ]]; then
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:normal
  dunstify -t 1000 "Turn on Workrave"
  pkill -f -9 "bash.*workrave_toggle.sh"
else
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:quiet
  INDEX=$(echo "15 minutes|30 minutes|1 hour|2 hours" | rofi -width -75 -sep '|' -dmenu -p "Suspend Workrave for > " -format i)
  TIME=900
  case INDEX in
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
      dunstify -t 1000 "No choice."
      exit 1
  esac
  dunstify -t 1000 "Turn off Workrave for $TIME seconds."
  sleep $TIME
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:normal
  dunstify -t 1000 "Turn on Workrave"
fi

