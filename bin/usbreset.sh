#!/bin/bash

sudo rmmod ehci_pci
sudo rmmod xhci_pci

sudo modprobe ehci_pci
sudo modprobe xhci_pci

sleep 2

xkb-switch -s us
