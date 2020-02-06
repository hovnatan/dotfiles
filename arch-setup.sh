#!/bin/bash

sudo pacman -Ry linux acpi_call

sudo pacman -Sy linux-lts acpi_call-lts
sudo mkinitcpio -p linux-lts
sudo grub-mkconfig -o /boot/grub/grub.cfg

sudo pacman -Sy networkmanager network-manager-applet os-prober openssh pepper-flash ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp tlp-rdw htop intel-gpu-tools libva-intel-driver libva-utils intel-media-driver xorg fortune-mod workrave feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub glew vtk xf86-video-intel rofi dunst zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift i3-wm i3status perl-anyevent-i3 qt5-styleplugins python-gobject aws-cli unzip imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wget ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks texlive-core texlive-langextra pandoc xorg-xinit pdfgrep xbindkeys ripgrep aria2 tk libjpeg-turbo ctags time yarn ranger w3m elinks odt2txt mediainfo highlight ffmpegthumbnailer atool yapf pandoc-citeproc luarocks tcl tk libimagequant dex mps-youtube fwupd vlc bash-language-server ansifilter xcape lsof rsync unrar perl-image-exiftool meld libvdpau-va-gl vulkan-intel ntp jre-openjdk unclutter xss-lock pacman-contrib libappindicator-gtk3 blueman udisks2 udiskie tldr rofimoji

sudo pacman -Sy base-devel clang llvm cmake gdb valgrind perf strace cppcheck ccache eigen3 boost

sudo pacman -Sy python-pip python-sh python-language-server autopep8 python-pynput python-pyperclip ipython python-pydbus python-systemd

sudo pacman -Sy ttf-croscore ttf-font-awesome awesome-terminal-fonts # noto-fonts-cjk noto-fonts noto-fonts-emoji ttf-liberation

# latex language server
sudo luarocks install --server=http://luarocks.org/dev digestif

sudo pip3 install pysnooper neovim-remote

sudo systemctl enable ntpd.service
sudo systemctl enable NetworkManager.service
sudo systemctl enable bluetooth
systemctl --user enable pulseaudio

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
rm -rf ~/.config/yay
ln -sf ~/.dotfiles/.config/yay/ ~/.config/yay

cd ~/.dotfiles
git clone git@github.com:hovnatan/i3-volume.git

yay -S skype wd719x-firmware aic94xx-firmware zoom i3ipc-python-git libinput-gestures clipster xcwd-git foxitreader i3lock-color gruvbox-icon-theme python-torchvision bear-git nerd-fonts-dejavu-complete ripgrep-all python-snakeviz subliminal vte3-ng dragon-drag-and-drop-git google-chrome ptags xkb-switch-git flacon freeoffice freetype2-cleartype mpv-mpris-git playerctl-git lnav
sudo grub-mkconfig -o /boot/grub/grub.cfg

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
# sudo mkinitcpio -p linux-lts
# sudo grub-mkconfig -o /boot/grub/grub.cfg
# sudo nvim /etc/systemd/sleep.conf
# AllowSuspendThenHibernate=yes
# HibernateDelaySec=1800
# sudo nvim /etc/systemd/logind.conf
# HandleLidSwitch=suspend-then-hibernate

# to use last grub edit /etc/default/grub
# GRUB_SAVEDEFAULT=true
# GRUB_DEFAULT=saved
# sudo grub-mkconfig -o /boot/grub/grub.cfg

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

# sudo cp ~/.dotfiles/etc/systemd/system/wakelock.service /etc/systemd/system/wakelock.service
# sudo systemctl enable /etc/systemd/system/wakelock.service
sudo mkdir -p /usr/local/share/kbd/keymaps
sudo cp ~/.dotfiles/usr/local/share/kbd/keymaps/caps_control.kmap /usr/local/share/kbd/keymaps/
sudo cp ~/.dotfiles/vconsole.conf /etc/


# terminal fun
# yay -S asciiquarium sl cmatrix

sudo systemctl enable tlp.service tlp-sleep.service NetworkManager-dispatcher.service
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket

# pacman best servers for armenia found by rankmirrors. Write in /etc/pacman.d/mirrorlist
# Server = http://mirror.metalgamer.eu/archlinux/$repo/os/$arch
# Server = http://archlinux.cu.be/$repo/os/$arch
# Server = http://arch.eckner.net/archlinux/$repo/os/$arch
# Server = http://archlinux.vi-di.fr/$repo/os/$arch
# Server = http://archlinux.mirrors.benatherton.com/$repo/os/$arch
# Server = http://mirrors.uni-plovdiv.net/archlinux/$repo/os/$arch

# for rankmirrors
# sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup
# sudo sh -c 'rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist'

# yay -S linux-clear-bin intel-ucode-clear
# sudo cp ~/.dotfiles/etc/systemd/system/disable-USB-wakeup.service /etc/systemd/system/
# sudo systemctl enable disable-USB-wakeup.service
