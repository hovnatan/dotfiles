#!/bin/bash

cd ~/Downloads
rm -rf Miniconda3-latest-Linux-x86_64.sh
rm -rf ~/miniconda3

VERSION="py39_4.9.2"
FILENAME="Miniconda3-${VERSION}-Linux-x86_64.sh"

wget https://repo.anaconda.com/miniconda/$FILENAME
bash ./$FILENAME -b

source ~/miniconda3/etc/profile.d/conda.sh
conda activate

conda install mamba

mamba update -y --all

# conda install -y pytorch torchvision cpuonly
mamba install -y pillow boost matplotlib scipy conda-build Cython sympy pandas shapely scikit-image pycairo cvxpy cvxopt scikit-learn
mamba install -y ipython rope ipdb pudb pynvim jupyter pylint pytest pytest-xdist pytest-cov coverage twine sphinx boto3 docker-compose
# conda install tbb tbb-devel cmake binutils_impl_linux-64 binutils_linux-64 gxx_linux-64 gcc_linux-64 nvcc_linux-64 libx11-common-cos6-x86_64 libx11-cos6-x86_64 libxdamage-cos6-x86_64 libxfixes-cos6-x86_64 libxxf86vm-cos6-x86_64 mesa-dri-drivers-cos6-x86_64 mesa-dri1-drivers-cos6-x86_64 mesa-libgl-cos6-x86_64 mesa-libgl-devel-cos6-x86_64 libselinux-cos6-x86_64

# pypng for indexed png, gitpython python wrapper for git
pip install pypng gitpython tensorboard sphinx-rtd-theme pylint-json2html pylint-pytest pytest-timeout pyenchant pretty_errors scalene opencv-python
pip install torch==1.8.1+cpu torchvision==0.9.1+cpu torchaudio==0.8.1 -f https://download.pytorch.org/whl/torch_stable.html


# also might be install sudo apt-get install -y libgl1-mesa-dev
# conda env export | cut -f 1 -d '=' > ~/.dotfiles/conda_environment.yml
# conda env update --file ~/.dotfiles/conda_environment.yml
# ln -s /usr/local/share/terminfo/x/xterm-termite ~/miniconda3/share/terminfo/x/
