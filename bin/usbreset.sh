#!/bin/sh

sudo $HOME/.dotfiles/bin/usbmodreset.sh

echo "Waiting for 5 seconds."
sleep 5

$HOME/.dotfiles/bin/setkmap.sh
