#!/bin/bash

grub-mkconfig -o /boot/grub/grub.cfg

sudo pacman -Sy networkmanager os-prober openssh pepper-flash ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools libva-intel-driver libva-utils intel-media-driver xorg fortune-mod workrave feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub glew vtk xf86-video-intel rofi dunst zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift chromium i3-wm i3status perl-anyevent-i3 qt5-styleplugins python-gobject aws-cli unzip xautolock imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso libreoffice-fresh inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wget ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks texlive-core texlive-langextra pandoc xorg-xinit pdfgrep xbindkeys ripgrep aria2 tk libjpeg-turbo ctags time autojump yarn ranger w3m elinks odt2txt mediainfo highlight ffmpegthumbnailer atool yapf vte3 pandoc-citeproc luarocks

sudo pacman -Sy base-devel clang llvm cmake gdb valgrind perf cppcheck ccache eigen3 boost

sudo pacman -Sy ipython python-pip python-sh python-language-server python-ipdb cython autopep8

sudo pacman -Sy python-numpy python-matplotlib python-scipy python-scikit-learn python-pandas

sudo pacman -Sy opencv python-pytorch

sudo pacman -Sy ttf-ubuntu-font-family ttf-hack ttf-dejavu ttf-freefont terminus-font ttf-arphic-uming ttf-baekmuk noto-fonts-emoji ttf-liberation otf-font-awesome

# latex language server
sudo luarocks install --server=http://luarocks.org/dev digestif

sudo pip3 install pysnooper

sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d
#Uncomment  export FREETYPE_PROPERTIES="truetype:interpreter-version=40"
sudo nvim  /etc/profile.d/freetype2.sh

#win fonts
#wget https://aur.archlinux.org/cgit/aur.git/snapshot/ttf-ms-win10.tar.gz
#tar xf ttf-ms-win10.tar.gz
#cd ttf-ms-win10
#mv ~/fonts/* .
#makepkg -Acs
#sudo pacman -U ttf-ms-win10 ttf-ms-win10-other

sudo systemctl enable tlp.service
sudo systemctl enable NetworkManager.service
systemctl --user enable pulseaudio

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

cd ~/.dotfiles
git clone https://github.com/hastinbe/i3-volume.git

cd ~/Downloads
git clone --recursive https://github.com/hovnatan/termite
cd termite
make
sudo make install

# change tar.gz to tar and specify makeflags to correct number of cores
sudo nvim /etc/makepkg.conf
wget https://www.dropbox.com/download?dl=packages/dropbox.py
yay -S skype wd719x-firmware aic94xx-firmware zoom i3ipc-python libinput-gestures clipster xcwd-git foxitreader i3lock-color gruvbox-icon-theme python-torchvision bear-git nerd-fonts-dejavu-complete ripgrep-all
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

# remove orphans
# sudo pacman -Rns (pacman -Qtdq)
# remove cache
# yay -Sc
