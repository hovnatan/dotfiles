#!/usr/bin/env bash

PLATFORM="aarm64"
PLATFORM="amd64"

docker build --platform="linux/$PLATFORM" --build-arg UNAME=$USER --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t hk_dev_env .
