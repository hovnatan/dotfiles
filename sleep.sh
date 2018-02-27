#!/bin/sh

case $1/$2 in
    pre/*)
#   systemctl stop NetworkManager.service
#        modprobe -r r8169
        ;;
    post/*) 
#        modprobe r8169
	/home/hovnatan/Dropbox/scripts/init-headphone
#	echo "Waking up from $2..."
#  systemctl start NetworkManager.service
        ;;
esac
