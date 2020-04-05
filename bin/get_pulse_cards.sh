#!/bin/bash

CARDS=$(pacmd list-cards)
INDICES=$(echo "$CARDS" | grep "index:" | awk '{print $2}')
CURRENT_PROFILES=""
while read LINE
do
  PROFILE=$(echo "$CARDS" |
        awk -W posix '/^[ \t]+index: /{insink = $2 == "'$LINE'"}
          /^[ \t]+active profile: / && insink {gsub("<|>", ""); print $3; exit}')
  DESCRIPTION=$(echo "$CARDS" |
        awk -W posix '/^[ \t]+index: /{insink = $2 == "'$LINE'"}
          /^[ \t]+device.description = / && insink {gsub("\"", ""); print $3; exit}')
  CURRENT_LINE="$LINE $DESCRIPTION $PROFILE"
  if [[ "$CURRENT_PROFILES" == "" ]]; then
    CURRENT_PROFILES="$CURRENT_LINE"
  else
    CURRENT_PROFILES="$CURRENT_PROFILES
$CURRENT_LINE"
  fi
done <<< "$INDICES"
echo "$CURRENT_PROFILES"
