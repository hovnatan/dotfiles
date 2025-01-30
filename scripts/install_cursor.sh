#!/usr/bin/env bash

set -euo pipefail

CURSOR_SVG="$HOME/opt/share/cursor.svg"
CURSOR_APP_IMAGE="$HOME/opt/bin/cursor.AppImage"
DESKTOP_FILE="$HOME/.local/share/applications/cursor.desktop"

mkdir -p "$(dirname "$CURSOR_APP_IMAGE")"
wget -O "$CURSOR_APP_IMAGE" "https://downloader.cursor.sh/linux/appImage/x64"
chmod +x "$CURSOR_APP_IMAGE"

if [ ! -f "$CURSOR_SVG" ]; then
    mkdir -p "$(dirname "$CURSOR_SVG")"
    wget -O "$CURSOR_SVG" "https://mintlify.s3-us-west-1.amazonaws.com/cursor/images/logo/app-logo.svg"
fi

if [ ! -f "$DESKTOP_FILE" ]; then
    mkdir -p "$(dirname "$DESKTOP_FILE")"
    cat << EOL > "$DESKTOP_FILE"
[Desktop Entry]
Name=Cursor
Exec=$CURSOR_APP_IMAGE --no-sandbox
Icon=$CURSOR_SVG
Type=Application
Categories=Development;
EOL
    update-desktop-database "$(dirname "$DESKTOP_FILE")"
fi