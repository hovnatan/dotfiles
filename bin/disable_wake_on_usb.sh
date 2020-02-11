#!/bin/bash

CONTENTS=$(tail -n +2 /proc/acpi/wakeup)
while read line; do
  if [[ "$line" == *"enabled"* && "$line" != *"SLPB"* && "$line" != *"LID"* ]]; then
    DEVICE=$(echo "$line" | cut -f1)
    echo "$DEVICE" > /proc/acpi/wakeup
  fi
done <<< "$CONTENTS"
