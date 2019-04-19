#!/bin/bash

sudo rmmod ehci_pci
#sudo rmmod xhci_pci

sudo modprobe ehci_pci
#sudo modprobe xhci_pci

setxkbmap -layout "us,am" -variant ",phonetic-alt" -option "ctrl:nocaps"
