FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y sudo

ARG USER=hovnatan

RUN adduser --disabled-password --gecos '' $USER
RUN adduser $USER sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers


USER $USER
WORKDIR /home/$USER

COPY --chown=$USER . .dotfiles/
RUN .dotfiles/ubuntu2204_setup.sh
