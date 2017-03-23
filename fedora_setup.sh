#!/bin/bash

dnf install calibre htop nautilus-open-terminal transmission python3-devel git-cola recoll djvulibre antiword unzip libxslt-python mpv

# video acceleration
dnf install vdpauinfo libva-vdpau-driver libva-utils

# gstream plugins
dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf install gstreamer{1,}-{ffmpeg,libav,plugins-{good,ugly,bad{,-free,-nonfree}}} --setopt=strict=0
dnf install gstreamer{1,}-{plugin-crystalhd,ffmpeg,plugins-{good,ugly,bad{,-free,-nonfree,-freeworld,-extras}{,-extras}}} libmpg123 lame-libs --setopt=strict=0

pip2 install epub 

# nvim
dnf install nvim
mkdir -p ~/.config/nvim/autoload ~/.config/nvim/bundle && \
curl -LSso ~/.config/nvim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
cd ~/.config/nvim
git clone https://github.com/kien/ctrlp.vim.git bundle/ctrlp.vim

# tmux 
dnf install tmux xclip 
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm 

# fish
dnf config-manager --add-repo http://download.opensuse.org/repositories/shells:fish:release:2/Fedora_25/shells:fish:release:2.repo
dnf install fish
