FROM ubuntu:22.04

RUN apt-config dump | grep -we Recommends -e Suggests | sed s/1/0/ | tee /etc/apt/apt.conf.d/99norecommend
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,target=/var/cache/apt \
    DEBIAN_FRONTEND=noninteractive \
    apt-get update \
    && apt-get install -y sudo

ARG USER=hovnatan

RUN adduser --disabled-password --gecos '' $USER
RUN adduser $USER sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER $USER
WORKDIR /home/$USER

COPY --chown=$USER .npmrc ./
COPY --chown=$USER ubuntu2204_setup.sh ./
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/home/$USER/.cargo/registry \
    --mount=type=cache,target=/home/$USER/.cache \
    DEBIAN_FRONTEND=noninteractive \
    ./ubuntu2204_setup.sh \
    && rm ubuntu2204_setup.sh

COPY --chown=$USER . .dotfiles/
RUN .dotfiles/setup.sh
