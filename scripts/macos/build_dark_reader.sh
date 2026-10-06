#!/usr/bin/env bash
#
# Build the Dark Reader Chrome extension from source, at a pinned commit, into
# a directory Chrome loads as an unpacked extension. What runs on every page
# (<all_urls>) is then the commit named below, built here, and changes only
# when the pin does; the Chrome Web Store copy updates itself.
#
#   version + commit (below)
#        |  git fetch --depth 1 <commit>      a temp directory, removed at exit
#        v
#   github.com/darkreader/darkreader
#        |  npm ci --ignore-scripts           package-lock.json's hashes
#        |  node tasks/cli.js build --release --chrome-mv3
#        v
#   build/release/chrome-mv3/                 manifest version == the pin, or fail
#        |  copied beside the old one, then renamed over it
#        v
#   ~/.local/share/dark-reader/chrome-mv3/    chrome://extensions > Load unpacked
#   ~/.local/share/dark-reader/built          "<commit> <build flags>"
#
# Run by dotup (scripts/setup_user_symlinks.sh, macOS). `built` already naming
# this pin: one line and nothing else, no network. So a build happens once per
# pin per machine, about 15 s.
#
# In scripts/macos because the Macs are where Chrome is; nothing in the build
# is macOS-specific.
#
# Once per Chrome profile, by hand (Chrome installs an unpacked extension from
# its own UI only; branded Chrome 137+ ignores --load-extension):
#   1. chrome://extensions: remove or turn off the Web Store Dark Reader, or
#      both darken the page
#   2. Developer mode on, "Load unpacked", cmd+shift+G, paste the path above
# After a later build: the reload arrow on its card there, or restart Chrome.
#
# The path must stay as it is: Chrome derives an unpacked extension's ID from
# its real path, and the settings are stored under the ID. That is also why
# the directory is renamed into place, not a symlink to a per-version one.
# Unpacked extensions are not synced between machines; Dark Reader's own
# settings export (More > Manage settings) carries them over.
#
# To upgrade: pick a tag, read the changes, set both lines, run this script.
#   git ls-remote --tags https://github.com/darkreader/darkreader.git 'v4.9.*' | tail
#   https://github.com/darkreader/darkreader/compare/v<old>...v<new>
#
# Needs git, node and npm (nix/flake.nix).
# Logs a build to ~/.dotfiles/.logs/<UTC>_build_dark_reader/events.log.
# Usage: scripts/macos/build_dark_reader.sh

set -euo pipefail
shopt -s extglob

# --- the pin ------------------------------------------------------------------

# The commit is what is fetched; the version is checked against the built
# manifest, so a bump that changes one line and not the other fails.
version=4.9.133
commit=92637d8c3fbb210853c005e3f25dbbec46dd21fc

repo=https://github.com/darkreader/darkreader.git
# MV3: Chrome no longer runs MV2 extensions.
flags=(--release --chrome-mv3)
platform=chrome-mv3

data="$HOME/.local/share/dark-reader"
dest="$data/$platform"
stamp="$data/built"
want="$commit ${flags[*]}"

# --- up to date? --------------------------------------------------------------

# Nothing is done, so nothing is logged: dotup runs this every time.
if [ -f "$dest/manifest.json" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
  echo "Dark Reader $version already built ($dest)"
  exit 0
fi

# --- build --------------------------------------------------------------------

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/../lib/event_log.sh"
event_log_start build_dark_reader
die() {
  log "ERROR $*" >&2
  exit 1
}

# logged <command...>: run it, each line of its output into the log, without
# the colour codes Dark Reader's build writes even to a pipe. Its exit status
# is the command's (pipefail).
logged() {
  local line
  "$@" 2>&1 | while IFS= read -r line; do
    log "  ${line//$'\e['*([0-9;])m/}"
  done
}

for cmd in git node npm; do
  command -v "$cmd" >/dev/null || die "$cmd not found; it comes from nix/flake.nix: run dotup, or see README.md \"Nix packages\""
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
src="$work/src"

log "Dark Reader $version ($commit) -> $dest; node $(node --version), npm $(npm --version)"

# By commit, not by tag: a tag can be moved upstream, a hash cannot.
log "fetch $repo"
git init --quiet "$src"
logged git -C "$src" fetch --quiet --depth 1 "$repo" "$commit" \
  || die "cannot fetch $commit from $repo (network, or the commit is gone upstream)"
git -C "$src" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
got=$(git -C "$src" rev-parse HEAD)
[ "$got" = "$commit" ] || die "fetched $got, not the pinned $commit"

# npm ci installs exactly package-lock.json, each tarball checked against its
# hash there, and fails if package.json disagrees. --ignore-scripts: no
# dependency's install script runs (upstream's own tasks pass it too).
log "npm ci"
(cd "$src" && logged npm ci --ignore-scripts --no-audit --no-fund) \
  || die "npm ci failed (output above)"

# As upstream's `npm run build`, for the one platform.
log "build ${flags[*]}"
(cd "$src" && logged node --max-old-space-size=3072 tasks/cli.js build "${flags[@]}") \
  || die "the build failed (output above)"

# --- check, then swap in ------------------------------------------------------

out="$src/build/release/$platform"
[ -f "$out/manifest.json" ] \
  || die "the build left no $out/manifest.json: upstream's output layout changed (tasks/paths.js there); update this script"
built=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version' "$out/manifest.json")
[ "$built" = "$version" ] \
  || die "built version $built, pinned $version: version and commit at the top of this script disagree"

# Copied onto the destination's filesystem first, so the renames are quick and
# a kill mid-copy leaves the old extension whole. The stamp goes last: a run
# killed before it rebuilds next time.
mkdir -p "$data"
rm -rf "$dest.new" "$dest.old"
cp -R "$out" "$dest.new"
first=1
if [ -e "$dest" ]; then
  first=0
  mv "$dest" "$dest.old"
fi
mv "$dest.new" "$dest"
rm -rf "$dest.old"
printf '%s\n' "$want" >"$stamp.new"
mv "$stamp.new" "$stamp"

log "built Dark Reader $version in $dest"
if [ "$first" -eq 1 ]; then
  log "to install, per Chrome profile: chrome://extensions, turn off the Web Store Dark Reader, Developer mode on, Load unpacked, cmd+shift+G, $dest"
else
  log "to pick it up: chrome://extensions, the reload arrow on Dark Reader's card (or restart Chrome)"
fi
