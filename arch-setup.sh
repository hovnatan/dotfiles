#!/bin/bash

grub-mkconfig -o /boot/grub/grub.cfg

sudo pacman -Sy networkmanager os-prober openssh pepper-flash ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools libva-intel-driver libva-utils intel-media-driver xorg fortune-mod workrave feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub glew vtk xf86-video-intel rofi dunst zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift i3-wm i3status perl-anyevent-i3 qt5-styleplugins python-gobject aws-cli unzip xautolock imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso libreoffice-fresh inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wget ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks texlive-core texlive-langextra pandoc xorg-xinit pdfgrep xbindkeys ripgrep aria2 tk libjpeg-turbo ctags time autojump yarn ranger w3m elinks odt2txt mediainfo highlight ffmpegthumbnailer atool yapf pandoc-citeproc luarocks tcl tk libimagequant dex mps-youtube fwupd vlc bash-language-server ansifilter xcape

sudo pacman -Sy base-devel clang llvm cmake gdb valgrind perf strace cppcheck ccache eigen3 boost

sudo pacman -Sy ipython python-pip python-sh python-language-server python-ipdb cython autopep8 python-pynput python-pyperclip

sudo pacman -Sy ttf-ubuntu-font-family ttf-hack ttf-dejavu ttf-freefont terminus-font ttf-arphic-uming ttf-baekmuk noto-fonts-emoji ttf-liberation awesome-terminal-fonts

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
rm -rf ~/.config/yay
ln -sf ~/.dotfiles/.config/yay/ ~/.config/yay

cd ~/.dotfiles
git clone git@github.com:hovnatan/i3-volume.git

# change tar.gz to tar and specify makeflags to correct number of cores
sudo nvim /etc/makepkg.conf
# uncomment color
sudo nvim /etc/pacman.conf
wget https://www.dropbox.com/download?dl=packages/dropbox.py
yay -S skype wd719x-firmware aic94xx-firmware zoom i3ipc-python-git libinput-gestures clipster xcwd-git foxitreader i3lock-color gruvbox-icon-theme python-torchvision bear-git nerd-fonts-dejavu-complete ripgrep-all python-snakeviz subliminal vte3-ng dragon-drag-and-drop-git google-chrome
sudo ln -s /usr/bin/google-chrome-stable /usr/bin/chromium

sudo mkinitcpio -p linux

cd ~/Downloads
git clone --recursive https://github.com/hovnatan/termite
cd termite
make
sudo make install

cd ~/Downloads
aria2c -x 8 -s 8 https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash ./Miniconda3-latest-Linux-x86_64.sh
ln -s ~/.dotfiles/.condarc ~/.condarc
conda update --all
import_miniconda
conda install pytorch torchvision opencv pillow yapf pylint jedi ipython rope boost tbb tbb-devel cmake conda-build Cython ipdb sortedcontainers neovim matplotlib h5py scipy

conda install binutils_impl_linux-64 binutils_linux-64 gxx_linux-64 gcc_linux-64 libx11-common-cos6-x86_64 libx11-cos6-x86_64 libxdamage-cos6-x86_64 libxfixes-cos6-x86_64 libxxf86vm-cos6-x86_64 mesa-dri-drivers-cos6-x86_64 mesa-dri1-drivers-cos6-x86_64 mesa-libgl-cos6-x86_64 mesa-libgl-devel-cos6-x86_64 libselinux-cos6-x86_64
# conda env export | cut -f 1 -d '=' > ~/.dotfiles/conda_environment.yml
# conda env update --file ~/.dotfiles/conda_environment.yml
ln -s /usr/local/share/terminfo/x/xterm-termite ~/miniconda3/share/terminfo/x/
# run import_miniconda fish shell integration
# for bash
# run source /opt/miniconda3/etc/profile.d/conda.sh
# conda activate

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
