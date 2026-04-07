#!/bin/bash

set -euo pipefail

SSH_DIR="$HOME/.ssh_pinggy"
mkdir -p "$SSH_DIR"
HOST_KEY="$SSH_DIR/host_key"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
PUB_KEY_URL="https://raw.githubusercontent.com/hovnatan/dotfiles/refs/heads/main/.ssh/id_ed25519.pub"
SSHD_PORT=2222

# Generate host key if it doesn't exist
if [ ! -f "$HOST_KEY" ]; then
    echo "Generating host key..."
    ssh-keygen -t ed25519 -f "$HOST_KEY" -N ""
else
    echo "Host key already exists at $HOST_KEY"
fi

# Fetch the public key and create authorized_keys
echo "Fetching public key from GitHub..."
curl -fsSL "$PUB_KEY_URL" > "$AUTHORIZED_KEYS"
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

# Start Pinggy tunnel
echo "Starting Pinggy tunnel..."
ssh -p 443 -R0:localhost:$SSHD_PORT tcp@a.pinggy.io

# to connect: ssh -i <private-key-file> -p <pinggy-port> <remote-user>@<pinggy-hostname>