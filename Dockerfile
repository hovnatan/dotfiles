FROM ubuntu:24.04

RUN apt-get update && apt-get install -y apt-utils adduser

RUN yes | unminimize

RUN apt-config dump | grep -we Recommends -e Suggests | sed s/1/0/ | tee /etc/apt/apt.conf.d/99norecommend
RUN rm -f /etc/apt/apt.conf.d/docker-clean

RUN sed -i -e 's/http:\/\/archive\.ubuntu\.com\/ubuntu\//mirror:\/\/mirrors\.ubuntu\.com\/mirrors\.txt/' /etc/apt/sources.list

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

COPY ./scripts/ubuntu2404_setup.sh ./
RUN --mount=type=cache,target=/var/cache/apt ./ubuntu2404_setup.sh && rm ubuntu2404_setup.sh

RUN echo 'debconf debconf/frontend select readline' | debconf-set-selections

RUN deluser --remove-home ubuntu

ARG UNAME
ARG UID
ARG GID

RUN groupadd --gid $GID -o $UNAME
RUN adduser --uid $UID --gid $GID --disabled-password --gecos '' $UNAME
RUN adduser $UNAME sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER $UNAME
WORKDIR /home/$UNAME

ENTRYPOINT ["/bin/bash", "-l"]