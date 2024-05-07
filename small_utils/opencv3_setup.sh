#!/bin/bash

sudo apt -y install python3-pip jupyter-notebook jupyter-core python3-pandas python3-boto cython3 spyder3 python3-numpy python-numpy
sudo apt -y install build-essential cppcheck automake clang-tools clang-format valgrind gfortran checkinstall cmake libboost-all-dev ccache pkg-config
sudo apt -y install libopenblas-dev tk-dev libtbb-dev libeigen3-dev zlib1g-dev libjpeg-dev libpng-dev libtiff5-dev liblapacke-dev libblas-dev libatlas-base-dev libhdf5-dev
sudo apt -y install libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libavresample-dev


cmake  -DWITH_TBB=ON -DWITH_GDAL=OFF -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DWITH_MATLAB=OFF -DOPENCV_EXTRA_MODULES_PATH=/home/hovnatan/Downloads/opencv_contrib-3.4.11/modules ..
