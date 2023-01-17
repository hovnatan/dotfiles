FROM ubuntu:22.04

RUN apt-get update && apt-get install -y apt-utils

RUN yes | unminimize


RUN apt-config dump | grep -we Recommends -e Suggests | sed s/1/0/ | tee /etc/apt/apt.conf.d/99norecommend
RUN rm -f /etc/apt/apt.conf.d/docker-clean

RUN sed -i -e 's/http:\/\/archive\.ubuntu\.com\/ubuntu\//mirror:\/\/mirrors\.ubuntu\.com\/mirrors\.txt/' /etc/apt/sources.list

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

COPY ubuntu2204_setup.sh ./
RUN --mount=type=cache,target=/var/cache/apt \
    ./ubuntu2204_setup.sh \
    && rm ubuntu2204_setup.sh

RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg  add - && apt-get update -y && apt-get install google-cloud-cli -y

RUN echo 'debconf debconf/frontend select readline' | debconf-set-selections

ARG USER=hovnatan

RUN adduser --disabled-password --gecos '' $USER
RUN adduser $USER sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER $USER
WORKDIR /home/$USER

ENV TERM=alacritty

ENTRYPOINT ["/bin/bash", "-l"]
