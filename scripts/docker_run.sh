#!/usr/bin/env bash

NAME=hk_dev_env

HOME=Users

mkdir -p /$HOME/$USER/Dropbox/${NAME}_container_in_out
mkdir -p /$HOME/$USER/${NAME}_container_in_out

docker stop $NAME
docker rm $NAME


docker run --hostname $NAME --volume=/$HOME/$USER/${NAME}_container_in_out:/home/$USER --volume=/$HOME/$USER/Dropbox/${NAME}_container_in_out:/home/$USER/Dropbox/${NAME}_container_in_out -p 8888:8888 -ti --name=$NAME $NAME
