#!/usr/bin/env bash

# The Dockerfile lives in docker/ but COPYs scripts/ubuntu2404_setup.sh, so the
# build context stays the repo root no matter where this is run from.
dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# PLATFORM="aarm64"
# PLATFORM="amd64"
# docker build --platform="linux/$PLATFORM" --build-arg UNAME=$USER --build-arg UID=$(id -u) --build-arg GID=$(id -g) -f "$dotfiles_dir/docker/Dockerfile" -t hk_dev_env "$dotfiles_dir"

docker build --build-arg UNAME=$USER --build-arg UID=$(id -u) --build-arg GID=$(id -g) -f "$dotfiles_dir/docker/Dockerfile" -t hk_dev_env "$dotfiles_dir"
