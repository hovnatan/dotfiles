#!/bin/env bash

# set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace

CONFIG="$1"
OPTION="$2"
COLOR_PATH="$3"
cat "$COLOR_PATH" > "$CONFIG"
echo >> "$CONFIG"
cat "$OPTION" >> "$CONFIG"
