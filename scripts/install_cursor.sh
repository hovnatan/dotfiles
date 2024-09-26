#!/usr/bin/env bash

mkdir -p ~/opt/bin
mkdir -p ~/opt/share

wget -O ~/opt/share/cursor.svg "https://mintlify.s3-us-west-1.amazonaws.com/cursor/images/logo/app-logo.svg"

wget -O ~/opt/bin/cursor.AppImage "https://downloader.cursor.sh/linux/appImage/x64"
chmod +x ~/opt/bin/cursor.AppImage

ln -sf ~/.dotfiles/.local/share/applications/cursor.desktop ~/.local/share/applications
update-desktop-database
