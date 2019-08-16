#!/bin/sh

sudo rmmod ehci_pci
sudo rmmod xhci_pci

sudo modprobe ehci_pci
sudo modprobe xhci_pci
