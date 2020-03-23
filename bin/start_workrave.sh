#!/bin/bash

workrave &
while true; do
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:'normal'
  if [[ $? == 0 ]]; then
    break
  fi
  sleep 0.2
done
