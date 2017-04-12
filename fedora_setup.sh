#!/bin/bash

dnf install calibre htop nautilus-open-terminal transmission python3-devel git-cola mpv qt-creator gnome-tweak-tool fuse fuse-devel libcurl-devel automake

# video acceleration
dnf install vdpauinfo libva-vdpau-driver libva-utils

# gstream plugins
dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf install gstreamer{1,}-{ffmpeg,libav,plugins-{good,ugly,bad{,-free,-nonfree}}} --setopt=strict=0
dnf install gstreamer{1,}-{plugin-crystalhd,ffmpeg,plugins-{good,ugly,bad{,-free,-nonfree,-freeworld,-extras}{,-extras}}} libmpg123 lame-libs --setopt=strict=0

# nvim
dnf install nvim

# tmux 
dnf install tmux xclip 

# fish
dnf config-manager --add-repo http://download.opensuse.org/repositories/shells:fish:release:2/Fedora_25/shells:fish:release:2.repo
dnf install fish

# python spyder
dnf install python3-pip 
pip3 install spyder

# install recoll 
dnf install recoll djvulibre antiword unzip libxslt-python
dnf install python-pip
pip2 install epub 
