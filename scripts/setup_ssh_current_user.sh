#!/bin/bash

set -euo pipefail

SSH_DIR="$HOME/.ssh_current_user"
mkdir -p "$SSH_DIR"
HOST_KEY="$SSH_DIR/host_key"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
# Source of the authorized public key(s). Set PUB_KEY_FILES to one or more
# local files to use them as the base instead of fetching from PUB_KEY_URL.
# Example: PUB_KEY_FILES=("$HOME/.ssh/id_ed25519.pub" "/path/to/other.pub")
PUB_KEY_FILES=()
PUB_KEY_URL="https://raw.githubusercontent.com/hovnatan/dotfiles/refs/heads/main/.ssh/id_ed25519.pub"
SSHD_PORT=2222

# Generate host key if it doesn't exist
if [ ! -f "$HOST_KEY" ]; then
    echo "Generating host key..."
    ssh-keygen -t ed25519 -f "$HOST_KEY" -N ""
else
    echo "Host key already exists at $HOST_KEY"
fi

# Build authorized_keys from local files if given, otherwise fetch from the URL
if [ ${#PUB_KEY_FILES[@]} -gt 0 ]; then
    echo "Reading public key(s) from local file(s): ${PUB_KEY_FILES[*]}"
    cat "${PUB_KEY_FILES[@]}" > "$AUTHORIZED_KEYS"
else
    echo "Fetching public key from GitHub..."
    curl -fsSL "$PUB_KEY_URL" > "$AUTHORIZED_KEYS"
fi
chmod 600 "$AUTHORIZED_KEYS"
echo "Authorized key written to $AUTHORIZED_KEYS"

# Kill any existing sshd on this port
pkill -f "sshd -p $SSHD_PORT" 2>/dev/null || true

# Start sshd
echo "Starting sshd on port $SSHD_PORT..."
/usr/sbin/sshd -p "$SSHD_PORT" -h "$HOST_KEY" \
    -o "AuthorizedKeysFile=$AUTHORIZED_KEYS" \
    -o PubkeyAuthentication=yes \
    -o StrictModes=no

echo "sshd running on port $SSHD_PORT"


# if you want to connect to the local machine from the internet, you can use the following setup:

# Start Pinggy tunnel
# echo "Starting Pinggy tunnel..."
# ssh -p 443 -R0:localhost:$SSHD_PORT tcp@a.pinggy.io

# ssh -i <private-key-file> -p <pinggy-port> <remote-user>@<pinggy-hostname>
