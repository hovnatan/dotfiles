#!/bin/zsh

# 2-minute countdown timer (120 seconds)
countdown=120

while [ $countdown -gt 0 ]; do
  echo $countdown
  sleep 1
  ((countdown--))
done

echo "Time's up!"
