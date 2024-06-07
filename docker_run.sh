#!/usr/bin/env bash

NAME=hk_dev_env

mkdir -p /home/$USER/Dropbox/${NAME}_container_in_out
mkdir -p /home/$USER/${NAME}_container_in_out

docker stop $NAME
docker rm $NAME

docker run --hostname $NAME --volume=/home/$USER/${NAME}_container_in_out:/home/$USER --volume=/home/$USER/Dropbox/${NAME}_container_in_out:/home/$USER/Dropbox/${NAME}_container_in_out -p 8888:8888 -ti --name=$NAME $NAME
