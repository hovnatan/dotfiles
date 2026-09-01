#!/usr/bin/env bash
#
# install_gws.sh - the Google Workspace CLI (`gws`), which the `work-log`
# skill drives to read and write the daily work-log doc. Nothing else in
# these dotfiles needs it, so it is a separate opt-in install rather than
# part of setup_user_symlinks.sh.
#
# Two halves, and only the first is scriptable:
#   1. the binary        - this script
#   2. the OAuth grant   - a browser flow the user runs once per machine
#
# The credentials it produces (~/.config/gws/) are NOT in any dotfiles repo
# and must never be: private on GitHub still means stored elsewhere and kept
# in history forever. Re-run the auth flow on each new machine instead of
# copying them.

set -euo pipefail

PKG='@googleworkspace/cli'

# Already present is the common case - this box got it by hand before the
# script existed, into the system prefix rather than npm's current one.
if command -v gws >/dev/null 2>&1; then
  echo "gws already installed: $(command -v gws) -> $(gws --version 2>&1 | head -1)"
  echo "to upgrade: npm install -g $PKG@latest"
else
  command -v npm >/dev/null 2>&1 || {
    echo "npm not found - install node first (scripts/setup.sh, or your distro's nodejs)" >&2
    exit 1
  }
  # User prefix, so no sudo and nothing lands in /usr. Whatever `npm prefix
  # -g`/bin resolves to must be on PATH; on this setup that is ~/.local/bin,
  # which already carries the claude symlink.
  npm install -g "$PKG"
  hash -r
  command -v gws >/dev/null 2>&1 || {
    echo "installed, but gws is not on PATH - add $(npm prefix -g)/bin to it" >&2
    exit 1
  }
  echo "installed: $(command -v gws) -> $(gws --version 2>&1 | head -1)"
fi

# `auth status` is the only honest check: the binary alone proves nothing,
# and every gws call exits 2 until the grant exists.
echo
if gws auth status >/dev/null 2>&1; then
  # `auth status` dumps every enabled API (90+ lines here); keep the four
  # fields that say whether the work-log skill can actually run.
  echo "auth: already authenticated"
  gws auth status 2>/dev/null | sed '/^Using keyring backend/d' | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ("user", "project_id", "token_valid", "scope_count"):
    print(f"  {k}: {d.get(k)}")
'
else
  cat <<'MSG'
auth: NOT authenticated. Two steps, once per machine:

    gws auth setup     # GCP project + OAuth client (needs gcloud; skip if
                       # you already have a client_secret to point at)
    gws auth login     # opens a browser; authenticate AS the account that
                       # owns the work-log doc

Then re-check with `gws auth status`. Credentials land in ~/.config/gws/
(client_secret.json, credentials.enc, .encryption_key, token_cache.json) -
machine-local, never committed.

Authenticate as the document's owner, not a service account: edits then
carry the user's name in Google Docs version history and nothing needs
sharing.
MSG
fi
