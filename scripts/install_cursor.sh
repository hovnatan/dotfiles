#!/usr/bin/env bash

set -euo pipefail

mkdir -p ~/opt/share
wget -O ~/opt/share/cursor.svg "https://mintlify.s3-us-west-1.amazonaws.com/cursor/images/logo/app-logo.svg"

mkdir -p ~/opt/bin
wget -O ~/opt/bin/cursor.AppImage "https://downloader.cursor.sh/linux/appImage/x64"
chmod +x ~/opt/bin/cursor.AppImage

mkdir -p ~/.local/share/applications
cat << 'EOL' > ~/.local/share/applications/cursor.desktop
[Desktop Entry]
Name=Cursor
Exec=/home/hovnatan/opt/bin/cursor.AppImage --no-sandbox
Icon=/home/hovnatan/opt/share/cursor.svg
Type=Application
Categories=Development;
EOL
update-desktop-database ~/.local/share/applications