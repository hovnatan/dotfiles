sudo apt -y install spyder3 git-cola net-tools qtcreator chrome-gnome-shell lm-sensors tmux fish python3-gdal python-gdal neovim libfreetype6-dev gfortran libopenblas-dev liblapack-dev tk-dev cmake qtdeclarative5-dev libtbb-dev libeigen3-dev libvtk6-dev zlib1g-dev libjpeg-dev libwebp-dev libpng-dev libtiff5-dev libopenexr-dev libdc1394-22-dev libavcodec-dev libavformat-dev libswscale-dev libtheora-dev libvorbis-dev libxvidcore-dev libx264-dev yasm libopencore-amrnb-dev libopencore-amrwb-dev libv4l-dev libxine2-dev liblapack-dev liblapacke-dev checkinstall python3-numpy python-numpy libblas-dev gfortran libatlas-base-dev libboost-all-dev ccache fonts-hack-ttf build-essential cmake pkg-config unzip workrave redshift-gtk clang-tools clang-format libgdal-dev valgrind automake python3-pip python-pip neovim curl fortune-mod fortunes htop uget vainfo mpv jupyter-notebook jupyter-core python-ipykernel python3-pandas

sudo apt -y install evolution gnome-session vanilla-gnome-desktop gnome-clocks
#sudo update-alternatives --config gdm3.css

gsettings set org.gnome.desktop.input-sources xkb-options  "['caps:ctrl_modifier', 'grp:lalt_lshift_toggle', 'grp:switch']"
gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'us'), ('xkb', 'ru+phonetic_winkeys'), ('xkb', 'am+phonetic-alt')]"
gsettings set org.gnome.desktop.input-sources per-window "true"
gsettings set org.gnome.shell.app-switcher current-workspace-only true

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
sudo cp ~/.fzf/bin/fzf /usr/local/bin/
rm -rf ~/.fzf

sudo -H pip3 install pss

wget 'https://go.skype.com/skypeforlinux-64.deb'
sudo apt install ./skypeforlinux-64.deb
rm skypeforlinux-64.deb

