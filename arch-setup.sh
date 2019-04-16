#!/bin/bash

grub-mkconfig -o /boot/grub/grub.cfg

sudo pacman -Sy networkmanager os-prober openssh pepper-flash qtcreator spyder3 python-numpy ipython opencv gdal python-gdal ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools cmake libva-intel-driver libva-utils intel-media-driver terminus-font ttf-ubuntu-font-family ttf-hack ttf-dejavu xorg fortune-mod workrave base-devel feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub python-matplotlib glew vtk ccache boost eigen3 sudo xf86-video-intel rofi dunst vifm termite python-matplotlib zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift chromium i3-wm i3status perl-anyevent-i3 qt5ct python-gobject aws-cli unzip xautolock imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso ttf-liberation libreoffice-fresh inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wget python-scikit-learn python-scipy ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks texlive-core texlive-langextra pandoc xorg-xinit otf-font-awesome pdfgrep xbindkeys gdb cppcheck valgrind perf python-pip llvm

sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d
#Uncomment  export FREETYPE_PROPERTIES="truetype:interpreter-version=40"
sudo nvim  /etc/profile.d/freetype2.sh

sudo systemctl enable tlp.service
sudo systemctl enable NetworkManager.service
systemctl --user enable pulseaudio

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

cd ~/.dotfiles
git clone https://github.com/hastinbe/i3-volume.git

# change tar.gz to tar and specify makeflags to correct number of cores
sudo nvim /etc/makepkg.conf
#for dropbox
wget https://linux.dropbox.com/fedora/rpm-public-key.asc
gpg --import rpm-public-key.asc
yay -S skype git-cola dropbox wd719x-firmware aic94xx-firmware zoom xkblayout-state-git i3ipc-python libinput-gestures clipster xcwd-git foxitreader i3lock-color gruvbox-icon-theme pss-git
sudo mkinitcpio -p linux

#yay -S interception-caps2esc
#sudo cp ~/.dotfiles/udevmon.yaml /etc/
#sudo systemctl enable udevmon.service

# hibernate
# sudo fallocate -l 25G /swapfile
# sudo chmod 0600 /swapfile
# sudo swapon /swapfile
# sudo echo -n "/swapfile none swap defaults 0 0" >> /etc/fstab
# edit /etc/default/grub to have GRUB_CMDLINE_LINUX_DEFAULT="resume=UUID=c30e9703-6e2b-4374-acb2-f0f6b60b8e0a resume_offset=30332928"
# where offset can be get from
# sudo filefrag -v /swapfile | awk '{ if($1=="0:"){print $4} }'
# sudo nvim /etc/mkinitcpio.conf
# add in HOOKS resume before filesystems 
# sudo mkinitcpio -p linux
# sudo grub-mkconfig -o /boot/grub/grub.cfg
# sudo nvim /etc/systemd/sleep.conf
# AllowSuspendThenHibernate=yes
# HibernateDelaySec=1800
# sudo nvim /etc/systemd/logind.conf
# HandleLidSwitch=suspend-then-hibernate
