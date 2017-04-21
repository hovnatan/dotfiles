#!/bin/bash

sudo dnf install calibre htop nautilus-open-terminal transmission python3-devel git-cola mpv qt-creator gnome-tweak-tool fuse fuse-devel libcurl-devel automake go

# video acceleration
sudo dnf install vdpauinfo libva-vdpau-driver libva-utils

# gstream plugins
sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install gstreamer{1,}-{ffmpeg,libav,plugins-{good,ugly,bad{,-free,-nonfree}}} --setopt=strict=0
sudo dnf install gstreamer{1,}-{plugin-crystalhd,ffmpeg,plugins-{good,ugly,bad{,-free,-nonfree,-freeworld,-extras}{,-extras}}} libmpg123 lame-libs --setopt=strict=0

# nvim
sudo dnf install nvim

# tmux 
sudo dnf install tmux xclip 

# fish
sudo dnf config-manager --add-repo http://download.opensuse.org/repositories/shells:fish:release:2/Fedora_25/shells:fish:release:2.repo
sudo dnf install fish

# python spyder
sudo dnf install python3-pip 
sudo pip3 install spyder

# install recoll 
sudo dnf install recoll djvulibre antiword unzip libxslt-python
sudo dnf install python-pip
sudo pip2 install epub 

# gnome setup
gsettings set org.gnome.desktop.input-sources xkb-options  "['caps:ctrl_modifier', 'grp:lalt_lshift_toggle', 'grp:switch']"
gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'us'), ('xkb', 'ru+phonetic_winkeys'), ('xkb', 'am+phonetic-alt')]"
gsettings set org.gnome.desktop.input-sources per-window "true"
gsettings set org.gnome.software download-updates false
sudo systemctl disable dnf-makecache.timer
sudo systemctl disable dnf-makecache.service

# rc.local for trackpoint adjustment
sudo cp -i rc.local /etc/rc.d/

echo "Manually install goofys (s3 fs)"

echo "To install nvidia drivers 
 1. disable noveou
 2. sudo dnf install kernel-devel xorg-x11-drv-nvidia akmod-nvidia  
 3. sudo dracut --force /boot/initramfs-$(uname -r).img $(uname -r) "

echo "Install dash to dock and pixelsaver, topicons plus gnome extensions."

echo "Install freetype-freeworld for better font rendering."

