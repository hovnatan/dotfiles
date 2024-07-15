#!/usr/bin/env bash

docker build --build-arg UNAME=$USER --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t hk_dev_env .
