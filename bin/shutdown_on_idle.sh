#!/bin/bash

# modified from http://rohitrawat.com/automatically-shutting-down-google-cloud-platform-instance

threshold=0.4

count=0
while true
do
  load=$(uptime | sed -e 's/.*load average: //g' | awk '{ print $3 }')
  res=$(echo $load'<'$threshold | bc -l)
  if (( $res )); then
    echo "Idle minutes count = $count"
    ((count+=1))
  else
    count=0
  fi

  if (( count>10 ))
  then
    echo Shutting down
    # wait a little bit more before actually pulling the plug
    sleep 300
    sudo shutdown now
  fi
  sleep 60
done
