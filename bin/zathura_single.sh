#!/bin/bash

TABBED_XID=$(cat "$HOME/.tabbed.xid")

zathura -e $TABBED_XID "$1" &
