#!/bin/bash

mount /root/btrfs-top-lvl/
cd /root/btrfs-top-lvl/
btrfs subvolume delete /root/btrfs-top-lvl/root_062017/
btrfs subvolume snapshot -r /root/btrfs-top-lvl/root/ /root/btrfs-top-lvl/root_070217
cd ..
umount /root/btrfs-top-lvl/
