#!/bin/bash

sudo pacman -Sy networkmanager os-prober openssh gnome-weather pepper-flash qtcreator spyder3 python-numpy ipython opencv gdal python-gdal python-opencv ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools cmake libva-intel-driver libva-utils intel-media-driver ttf-ubuntu-font-family ttf-hack ttf-dejavu xorg fortune-mod workrave gnome-tweaks base-devel chrome-gnome-shell feh mpv xclip neovim fzf tmux youtube-dl gnome fish intel-ucode grub python-matplotlib glew vtk ccache boost eigen3 gdm

sudo systemctl enable tlp.service
sudo systemctl enable gdm.service
sudo systemctl enable NetworkManager.service

grub-mkconfig -o /boot/grub/grub.cfg

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

yay -S skype git-cola ttf-ms-fonts dropbox 
