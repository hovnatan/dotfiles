#!/bin/bash

grub-mkconfig -o /boot/grub/grub.cfg

sudo pacman -Sy networkmanager os-prober openssh pepper-flash ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools libva-intel-driver libva-utils intel-media-driver xorg fortune-mod workrave feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub glew vtk xf86-video-intel rofi dunst zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift i3-wm i3status perl-anyevent-i3 qt5-styleplugins python-gobject aws-cli unzip xautolock imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wget ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks texlive-core texlive-langextra pandoc xorg-xinit pdfgrep xbindkeys ripgrep aria2 tk libjpeg-turbo ctags time autojump yarn ranger w3m elinks odt2txt mediainfo highlight ffmpegthumbnailer atool yapf pandoc-citeproc luarocks tcl tk libimagequant dex mps-youtube fwupd vlc bash-language-server ansifilter xcape lsof rsync unrar perl-image-exiftool meld libvdpau-va-gl vulkan-intel ntp jre-openjdk

sudo pacman -Sy base-devel clang llvm cmake gdb valgrind perf strace cppcheck ccache eigen3 boost

sudo pacman -Sy ipython python-pip python-sh python-language-server python-ipdb cython autopep8 python-pynput python-pyperclip

sudo pacman -Sy ttf-croscore ttf-font-awesome awesome-terminal-fonts # noto-fonts noto-fonts-emoji ttf-liberation

# latex language server
sudo luarocks install --server=http://luarocks.org/dev digestif

sudo pip3 install pysnooper neovim-remote

sudo systemctl enable tlp.service
sudo systemctl enable ntpd.service
sudo systemctl enable NetworkManager.service
systemctl --user enable pulseaudio

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
rm -rf ~/.config/yay
ln -sf ~/.dotfiles/.config/yay/ ~/.config/yay

cd ~/.dotfiles
git clone git@github.com:hovnatan/i3-volume.git

# change tar.gz to tar and specify makeflags to correct number of cores
sudo nvim /etc/makepkg.conf
# uncomment color
sudo nvim /etc/pacman.conf
wget https://www.dropbox.com/download?dl=packages/dropbox.py
yay -S skype wd719x-firmware aic94xx-firmware zoom i3ipc-python-git libinput-gestures clipster xcwd-git foxitreader i3lock-color gruvbox-icon-theme python-torchvision bear-git nerd-fonts-dejavu-complete ripgrep-all python-snakeviz subliminal vte3-ng dragon-drag-and-drop-git google-chrome ptags xkb-switch-git flacon freeoffice freetype2-cleartype

sudo mkinitcpio -p linux

cd ~/Downloads
git clone --recursive https://github.com/hovnatan/termite
cd termite
make
sudo make install

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

# enabel timesync
sudo systemctl enable systemd-timesyncd.service
# set timezone
# timedatectl set-timezone (curl https://ipapi.co/timezone)

# to cleanup repo
# java -jar bfg-1.13.0.jar -b 32K ~/work/repo

sudo cp ~/.dotfiles/etc/systemd/system/wakelock.service /etc/systemd/system/wakelock.service
sudo systemctl enable /etc/systemd/system/wakelock.service
sudo mkdir -p /usr/local/share/kbd/keymaps
sudo cp ~/.dotfiles/usr/local/share/kbd/keymaps/caps_control.kmap /usr/local/share/kbd/keymaps/
sudo cp ~/.dotfiles/vconsole.conf /etc/
