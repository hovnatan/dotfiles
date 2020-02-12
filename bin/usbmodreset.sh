#!/bin/sh

rmmod ehci_pci
rmmod xhci_pci

modprobe ehci_pci
modprobe xhci_pci
