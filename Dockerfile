FROM ubuntu:22.04

RUN apt-config dump | grep -we Recommends -e Suggests | sed s/1/0/ | tee /etc/apt/apt.conf.d/99norecommend
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,target=/var/cache/apt DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y sudo && rm -rf /var/lib/apt/lists/*

ARG USER=hovnatan

RUN adduser --disabled-password --gecos '' $USER
RUN adduser $USER sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers


USER $USER
WORKDIR /home/$USER

COPY --chown=$USER . .dotfiles/
RUN --mount=type=cache,target=/var/cache/apt DEBIAN_FRONTEND=noninteractive .dotfiles/ubuntu2204_setup.sh && sudo rm -rf /var/lib/apt/lists/*

RUN .dotfiles/setup.sh
