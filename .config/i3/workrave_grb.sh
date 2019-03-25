#!/bin/bash

timer=$(dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.ConfigInterface.GetInt string:'timers/rest_break/limit' | grep int32 | awk '{print $2}')

elapsed=$(dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.GetTimerElapsed string:'restbreak' | grep int32 | awk '{print $2}')

seconds_left=`expr $timer - $elapsed`

minutes=$((seconds_left / 60))
seconds=$((seconds_left % 60))

notify-send -t 3000 "Left ${minutes}:${seconds}"

