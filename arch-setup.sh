#!/bin/bash

pacman -Sy networkmanager os-prober openssh pepper-flash qtcreator spyder3 python-numpy ipython opencv gdal python-gdal python-opencv ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools cmake libva-intel-driver libva-utils intel-media-driver ttf-ubuntu-font-family ttf-hack ttf-dejavu xorg fortune-mod workrave base-devel feh mpv xclip neovim fzf tmux youtube-dl fish intel-ucode grub python-matplotlib glew vtk ccache boost eigen3 sudo xf86-video-intel davfs2 rofi dunst vifm termite python-matplotlib lightdm lightdm-gtk-greeter zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift

#pacman -Sy gnome gnome-weather gnome-tweaks chrome-gnome-shell gdm

sudo systemctl enable tlp.service
sudo systemctl enable lightdm.service
sudo systemctl enable NetworkManager.service

grub-mkconfig -o /boot/grub/grub.cfg

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

cd ~
git clone https://github.com/hastinbe/i3-volume.git

yay -S skype git-cola ttf-ms-fonts dropbox wd719x-firmware aic94xx-firmware
sudo mkinitcpio -p linux

