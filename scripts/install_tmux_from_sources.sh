#!/usr/bin/env bash

set -e

sudo apt-get install -y build-essential libevent-dev libncurses-dev

cd Downloads

rm -rf tmux
git clone --depth 1 --branch 3.5a https://github.com/tmux/tmux.git
cd tmux
sh autogen.sh
./configure --prefix=$HOME/.local
make
make install
cd ..
