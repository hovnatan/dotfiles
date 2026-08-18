#!/usr/bin/env bash

# Hunspell on macOS: brew installs the binary but no dictionaries, and it
# exits with "Can't open affix or dictionary files" until en_US.aff/.dic
# exist somewhere on its search path. ~/Library/Spelling is on that path,
# so drop LibreOffice's en_US dictionary there. Idempotent: skips whatever
# is already in place; delete the .aff/.dic files to force a re-download.

set -euo pipefail

[ "$(uname)" = "Darwin" ] || { echo "macOS only"; exit 1; }

if ! command -v hunspell >/dev/null; then
  brew install hunspell
fi

dict_dir=~/Library/Spelling
base_url=https://raw.githubusercontent.com/LibreOffice/dictionaries/master/en
mkdir -p "$dict_dir"

for ext in aff dic; do
  f="$dict_dir/en_US.$ext"
  if [ -f "$f" ]; then
    echo "en_US.$ext already present"
    continue
  fi
  curl -sfL --max-time 60 -o "$f.tmp" "$base_url/en_US.$ext"
  mv "$f.tmp" "$f"
  echo "installed en_US.$ext"
done

echo "recieve" | hunspell -l -d en_US | grep -qx "recieve" \
  || { echo "hunspell self-test failed"; exit 1; }
echo "hunspell OK ($(hunspell --version | head -1))"
