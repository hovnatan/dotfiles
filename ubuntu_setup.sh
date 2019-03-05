#!/bin/bash

git update-index --assume-unchanged workrave.ini
#git update-index --no-assume-unchanged workrave.ini

sudo add-apt-repository -y ppa:saiarcot895/chromium-beta
sudo add-apt-repository -y ppa:rob-caelers/workrave
sudo apt update; sudo apt -y dist-upgrade


sudo apt -y install feh gimp pinta tmux fish neovim git-cola meld fortune-mod fortunes htop uget mpv vlc curl workrave workrave-gnome unzip lm-sensors jq awscli fonts-hack-ttf vainfo ubuntu-restricted-extras net-tools chrome-gnome-shell chromium-browser adobe-flashplugin
sudo apt -y install evolution gnome-session 
sudo apt -y install vanilla-gnome-desktop gnome-clocks
#sudo update-alternatives --config gdm3.css

sudo apt -y install python3-pip python-pip jupyter-notebook jupyter-core python-ipykernel python3-pandas python3-boto cython3 spyder3 python3-numpy python-numpy ipython3
sudo apt -y install build-essential cppcheck automake clang-tools clang-format valgrind gfortran checkinstall cmake libboost-all-dev ccache pkg-config 
sudo apt -y install libopenblas-dev tk-dev libtbb-dev libeigen3-dev zlib1g-dev libjpeg-dev libpng-dev libtiff5-dev liblapacke-dev libblas-dev libatlas-base-dev libhdf5-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev libncurses5-dev


git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --bin
sudo cp ~/.fzf/bin/fzf /usr/local/bin/
cp ~/.fzf/shell/key-bindings.fish ~/.config/fish/functions/fzf_key_bindings.fish
rm -rf ~/.fzf

sudo -H pip3 install pss

wget 'https://go.skype.com/skypeforlinux-64.deb'
sudo apt -y install ./skypeforlinux-64.deb
rm skypeforlinux-64.deb

# for qgis
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrep

# for Qt apps favorite on dock add to .desktop files StartupWMClass=QT...
#
# for pixel saver close button icon to work:
# cd ~/.local/share/gnome-shell/extensions/pixel-saver@deadalnix.me/themes
# mv Ambiance Ambiance.bak
# ln -s default Ambiance
# 
# to increase swap space:
# sudo swapoff -a
# sudo fallocate -l 24G /swapfile
# sudo mkswap /swapfile
# sudo swapon /swapfile

# for debug set to 0
# sudo nvim /etc/sysctl.d/10-ptrace.conf

#tracker daemon -t
#mkdir -p ~/.config/autostart
#cd ~/.config/autostart
#cp -v /etc/xdg/autostart/tracker-* ./
#for FILE in `ls`; do echo Hidden=true >> $FILE; done
#rm -rf ~/.cache/tracker ~/.local/share/tracker

#opencv install
#cmake -DWITH_TBB=ON -DWITH_IPP=ON -DWITH_GDAL=ON -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DWITH_MATLAB=OFF -DWITH_CUDA=OFF -DOPENCV_EXTRA_MODULES_PATH=/home/hovnatan/Downloads/opencv_contrib-3.4.1/modules/-DCMAKE_BUILD_TYPE=Release ..

# enable partner repos
# sudo apt install adobe-flashplugin 
#cd ~/.local/share/gnome-shell/extensions
#git clone https://github.com/deadalnix/pixel-saver.git
#mv pixel-saver/pixel-saver@deadalnix.me/ . 
#rm -rf pixel-saver
# sudo wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key|sudo apt-key add -
# echo "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-7 main" >> /etc/apt/sources.list
# sudo apt update
# sudo apt install clang-7 lldb-7 lld-7 clang-7 clang-tools-7 clang-7-doc libclang-common-7-dev libclang-7-dev libclang1-7 clang-format-7 python-clang-7
# sudo sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-7 100
# sudo sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-7 100
# make SRCDIR=build CFGDIR=/usr/share/cppcheck/ HAVE_RULES=yes CXXFLAGS="-O2 -DNDEBUG -Wall -Wno-sign-compare -Wno-unused-function" -j8
# sudo make install CFGDIR=/usr/share/cppcheck/ -j8

echo "Add google id from scripts/.profile"
echo "Edit /etc/default/avahi-daemon for disabling network discovery."
