#!/bin/bash

cd ~/Downloads
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash ./Miniconda3-latest-Linux-x86_64.sh

source ~/miniconda3/etc/profile.d/conda.sh
conda activate

conda update -y --all
conda install -y opencv pillow boost matplotlib scipy conda-build Cython sympy pandas shapely scikit-image imgaug pycairo cvxpy cvxopt scikit-learn
conda install -y yapf pylint jedi ipython rope ipdb pudb sortedcontainers matplotlib h5py future prettytable easydict pynvim jupyter colorama pyyaml numba cachetools packaging pytest pytest-xdist pytest-cov coverage twine sphinx boto3 docker-compose
# conda install tbb tbb-devel cmake binutils_impl_linux-64 binutils_linux-64 gxx_linux-64 gcc_linux-64 nvcc_linux-64 libx11-common-cos6-x86_64 libx11-cos6-x86_64 libxdamage-cos6-x86_64 libxfixes-cos6-x86_64 libxxf86vm-cos6-x86_64 mesa-dri-drivers-cos6-x86_64 mesa-dri1-drivers-cos6-x86_64 mesa-libgl-cos6-x86_64 mesa-libgl-devel-cos6-x86_64 libselinux-cos6-x86_64

conda install pytorch torchvision torchaudio cudatoolkit=11.0 -c pytorch

# pypng for indexed png, gitpython python wrapper for git
pip install pypng gitpython tensorboard sphinx-rtd-theme pylint-json2html pylint-pytest pyenchant


# also might be install sudo apt-get install -y libgl1-mesa-dev
# conda env export | cut -f 1 -d '=' > ~/.dotfiles/conda_environment.yml
# conda env update --file ~/.dotfiles/conda_environment.yml
# ln -s /usr/local/share/terminfo/x/xterm-termite ~/miniconda3/share/terminfo/x/
