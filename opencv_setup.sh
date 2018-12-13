# #for intel distribution installation
# # install miniconda
# conda update conda
# conda config --add channels intel
# conda create -n idp intelpython3_full python=3
# set -x PATH /home/hovnatan/miniconda3/bin $PATH
# source (conda info --root)/etc/fish/conf.d/conda.fish
# conda activate idp
# conda install conda install mkl-devel

# #install gdal 
# set -x PKG_CONFIG_PATH /home/hovnatan/miniconda3/envs/idp/lib/pkgconfig
# set -x CPPFLAGS -I/home/hovnatan/miniconda3/envs/idp/include/
# set -x CXXFLAGS -I/home/hovnatan/miniconda3/envs/idp/include/
# set -x CFLAGS -I/home/hovnatan/miniconda3/envs/idp/include/
# set -x LDFLAGS -L/home/hovnatan/miniconda3/envs/idp/lib/
# set -x LD_LIBRARY_PATH /home/hovnatan/miniconda3/envs/idp/lib/
# ./configure --prefix=/home/hovnatan/miniconda3/envs/idp/ --with-python=/home/hovnatan/miniconda3/envs/idp/bin/python3
# #install opencv 
# set -x CMAKE_PREFIX_PATH /home/hovnatan/miniconda3/envs/idp
# cmake ...... -WITH_PROTOBUFF=OFF for opencv
# cmake -DWITH_TBB=ON -DWITH_GDAL=ON -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DWITH_MATLAB=OFF -DOPENCV_EXTRA_MODULES_PATH=/home/hovnatan/Downloads/opencv_contrib-4.0.0/modules/ -DPYTHON3_EXECUTABLE=/home/hovnatan/miniconda3/envs/idp/bin/python3 -DPYTHON3_LIBRARY=/home/hovnatan/miniconda3/envs/idp/lib/libpython3.so -DPYTHON3_PACKAGES_PATH=/home/hovnatan/miniconda3/envs/idp/lib/python3.6/site-packages/ -DCMAKE_INSTALL_PREFIX=/home/hovnatan/miniconda3/envs/idp/ -DWITH_PROTOBUF=OFF ..

# Check PROJ4
wget http://download.osgeo.org/proj/proj-5.1.0.tar.gz
tar -xf proj-5.1.0.tar.gz
cd proj-5.1.0/
./configure
make -j16
sudo make install
sudo ldconfig
cd /home/"$(whoami)"

# GEOS
wget http://download.osgeo.org/geos/geos-3.6.2.tar.bz2
tar xf geos-3.6.2.tar.bz2
cd geos-3.6.2
./configure
make -j16
sudo make install
sudo ldconfig
cd /home/"$(whoami)"

# GDAL
wget http://download.osgeo.org/gdal/2.3.2/gdal-2.3.2.tar.xz
tar xvf gdal-2.3.2.tar.xz
cd gdal-2.3.2
./configure --with-python=/usr/bin/python3
make -j16
sudo make install
export LD_LIBRARY_PATH="/usr/local/lib"
sudo ldconfig

cd ./swig/python
sudo python3 setup.py build
sudo python3 setup.py install

cd /home/"$(whoami)"

# Download OpenCV contrib
mkdir opencv_contrib
cd opencv_contrib
wget https://github.com/opencv/opencv_contrib/archive/4.0.0.tar.gz
tar xf 4.0.0.tar.gz
cd ..

# Download openCV
wget https://github.com/opencv/opencv/archive/4.0.0.tar.gz
tar xf 4.0.0.tar.gz
cd opencv-4.0.0
mkdir build
cd build

# Make OpenCV
cmake  -DWITH_TBB=ON -DWITH_GDAL=ON -DBUILD_TESTS=OFF \
-DBUILD_PERF_TESTS=OFF -DWITH_MATLAB=OFF -DOPENCV_EXTRA_MODULES_PATH=/home/"$(whoami)"/opencv_contrib/opencv_contrib-4.0.0/modules/ ..
