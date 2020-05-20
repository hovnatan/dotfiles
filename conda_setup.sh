#!/bin/bash

cd ~/Downloads
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash ./Miniconda3-latest-Linux-x86_64.sh
ln -s ~/.dotfiles/.condarc ~/.condarc
import_miniconda
conda update --all
conda install pytorch torchvision opencv pillow boost matplotlib scipy conda-build Cython sympy pandas shapely scikit-image imgaug pycairo
conda install yapf pylint jedi ipython rope ipdb pudb sortedcontainers matplotlib h5py future prettytable easydict pynvim jupyter
conda install tbb tbb-devel cmake binutils_impl_linux-64 binutils_linux-64 gxx_linux-64 gcc_linux-64 nvcc_linux-64 libx11-common-cos6-x86_64 libx11-cos6-x86_64 libxdamage-cos6-x86_64 libxfixes-cos6-x86_64 libxxf86vm-cos6-x86_64 mesa-dri-drivers-cos6-x86_64 mesa-dri1-drivers-cos6-x86_64 mesa-libgl-cos6-x86_64 mesa-libgl-devel-cos6-x86_64 libselinux-cos6-x86_64

# pypng for indexed png, gitpython python wrapper for git
pip install pypng gitpython tensorboard

pip install git+git://github.com/ranger/ranger.git

cp ~/miniconda3/share/fzf/shell/key-bindings.fish ~/.config/fish/functions/fzf_key_bindings.fish

#also might be install sudo apt-get install -y libgl1-mesa-dev
# conda env export | cut -f 1 -d '=' > ~/.dotfiles/conda_environment.yml
# conda env update --file ~/.dotfiles/conda_environment.yml
# ln -s /usr/local/share/terminfo/x/xterm-termite ~/miniconda3/share/terminfo/x/
# run import_miniconda fish shell integration
# for bash
# run source /opt/miniconda3/etc/profile.d/conda.sh
# conda activate
<<<<<<< HEAD

# pypng for indexed png, gitpython python wrapper for git
pip install pypng gitpython tensorboard
