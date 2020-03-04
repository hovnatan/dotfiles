#!/bin/bash

if ! pkill trayer ; then
  trayer --edge top --align right --transparent true --width 20 --alpha 200 --expand false --height 30
fi
