FROM ubuntu:22.04

RUN echo "deb mirror://mirrors.ubuntu.com/mirrors.txt jammy main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb mirror://mirrors.ubuntu.com/mirrors.txt jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb mirror://mirrors.ubuntu.com/mirrors.txt jammy-security main restricted universe multiverse" >> /etc/apt/sources.list && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y sudo

ARG USER=hovnatan

RUN adduser --disabled-password --gecos '' $USER
RUN adduser $USER sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers


USER $USER
WORKDIR /home/$USER

COPY --chown=$USER . .dotfiles/
RUN DEBIAN_FRONTEND=noninteractive .dotfiles/ubuntu2204_setup.sh
