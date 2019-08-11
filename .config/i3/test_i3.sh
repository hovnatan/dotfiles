#!/bin/bash

for i in $(seq 1 20000)
do
   echo "Welcome $i times"
   python ./i3_custom_ipc_client.py next_w_on_ws
 done
