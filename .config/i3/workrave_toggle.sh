#!/bin/bash

new_mode="normal"
dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.GetOperationMode | grep normal
if [ $? -eq 0 ]; then
  new_mode="suspended"
fi

dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetOperationMode string:"${new_mode}"
