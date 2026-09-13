#!/usr/bin/env bash

for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
# Expanded into variables first: the one-liner from Docker's docs nests its
# quotes inside out, so the substitutions ran unquoted and the indentation of
# the continuation line leaked into the apt source line.
arch=$(dpkg --print-architecture)
# shellcheck disable=SC1091  # sourced for VERSION_CODENAME; not part of the repo
codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $codename stable" |
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

mkdir -p ~/.docker/completions
docker completion zsh > ~/.docker/completions/_docker
