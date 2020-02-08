#!/bin/bash

TO_SLEEP=300
CHECK_TIME=30
I=0
I_MAX=$((TO_SLEEP / CHECK_TIME))

while true; do
  sleep "$CHECK_TIME"
  xset dpms force off
  if acpi -b | grep Discharging ; then
    ((++I))
    if [[ "$I" == "$I_MAX" ]]; then
      systemctl suspend
    fi
  else
    I=0
  fi
done
