#!/bin/bash

sudo rmmod ehci_pci
sudo modprobe ehci_pci
setxkbmap -layout "us,am" -variant ",phonetic-alt" -option "ctrl:nocaps"
