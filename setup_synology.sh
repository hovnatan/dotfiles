#!/bin/bash

chmod 755 /var/services/homes/<HOME_DIR>

mkdir -p .ssh
touch ~/.ssh/authorized_keys

chmod 700 ~/.ssh
chmod 644 ~/.ssh/authorized_keys
