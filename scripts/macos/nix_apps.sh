#!/usr/bin/env bash
#
# nix_apps.sh -- mirror the Nix profile's .app bundles (mpv.app, from
# nix/flake.nix) into "~/Applications/Nix Apps" as real files, so Spotlight
# lists them. In the profile a bundle is links into /nix, a volume mounted
# nobrowse: Spotlight indexes nothing there and follows no link into it.
#
#   ~/.nix-profile/Applications/mpv.app      links into /nix/store
#        |  rsync -L         a link becomes the file it names
#        |        --checksum an unchanged file is left as it is
#        |        --delete   an app dropped from the flake goes
#   ~/Applications/Nix Apps/mpv.app
#
# A copy's launcher names store paths of the profile generation it was made
# from, so this runs after every change of the set: `dotup` does it
# (scripts/update.sh, nix_apply); after `nix profile upgrade` by hand, run
# it yourself. Safe to re-run. The directory is this script's alone:
# anything else put there is deleted.
#
# Logs each run to ~/.dotfiles/.logs/<UTC>_nix_apps/events.log
# (scripts/lib/event_log.sh).
#
# Usage: scripts/macos/nix_apps.sh

set -euo pipefail

[ "$(uname)" = "Darwin" ] || {
  echo "nix_apps.sh: macOS only" >&2
  exit 1
}

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/../lib/event_log.sh"
event_log_start nix_apps

src="$HOME/.nix-profile/Applications"
dst="$HOME/Applications/Nix Apps"
# Nix's rsync 3, part of the same set: Apple's /usr/bin/rsync is openrsync.
rsync="$HOME/.nix-profile/bin/rsync"

if [ ! -d "$src" ]; then
  if [ -d "$dst" ]; then
    rm -rf "$dst"
    log "removed $dst: the Nix profile has no apps"
  else
    log "nothing to do: the Nix profile has no apps"
  fi
  exit 0
fi

[ -x "$rsync" ] || {
  echo "nix_apps.sh: $rsync is missing; apply the Nix set first (nix/flake.nix lists rsync)" >&2
  exit 1
}

mkdir -p "$dst"
# The store's files are read-only; u+w lets the next run replace them.
changes=$("$rsync" -rLp --checksum --delete --chmod=u+w --itemize-changes "$src/" "$dst/")
if [ -z "$changes" ]; then
  log "unchanged: $dst"
else
  while IFS= read -r line; do
    log "$line"
  done <<<"$changes"
  log "updated: $dst"
fi
