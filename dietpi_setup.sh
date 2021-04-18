
sudo apt-get -y install tmux fish openssh-client
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get install -y nodejs

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install -y yarn

sudo apt-get install -y python2 python3-pip
pip3 install --user pylint yapf jedi neovim ueberzug

sudo update-alternatives --install /usr/bin/python python /usr/bin/python2 1
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 2

apt install python3-dev python3-pip
sudo apt-get -y install git build-essential cmake pkg-config checkinstall ccache
sudo apt-get -y install libjpeg-dev libpng-dev libtiff-dev
sudo apt-get -y install libprotobuf-dev protobuf-compiler
sudo apt-get -y install libv4l-dev
sudo apt-get -y install libeigen3-dev


git clone git@github.com:hovnatan/tracker.git

sudo apt install python3-numpy python3-flask python3-requests

apt install dphys-swapfile

sed -i 's/CONF_SWAPSIZE=100/CONF_SWAPSIZE=1024/g' /etc/dphys-swapfile
dphys-swapfile swapoff
dphys-swapfile start

wget https://github.com/opencv/opencv_contrib/archive/refs/tags/4.5.2.zip
unzip
unzip 4.5.2.zip
wget https://github.com/opencv/opencv/archive/refs/tags/4.5.2.tar.gz
tar xf 4.5.2.tar.gz


cd opencv-4.5.2/
mkdir build
cd build/

cmake -DOPENCV_EXTRA_MODULES_PATH=../../opencv_contrib-4.5.2/modules -DBUILD_TESTS=OFF -DINSTALL_PYTHON EXAMPLES=OFF -DOPENCV_ENABLE_NONFREE=ON -DBUILD_EXAMPLES=OFF -DBUILD_PERF_TESTS=OFF -DWITH_TENGINE=ON ..
make -j4
make install

