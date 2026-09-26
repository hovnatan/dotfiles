#!/usr/bin/env bash
#
# check_configs.sh -- parse checks for the config formats no other CI job
# covers (.github/workflows/configs.yml runs it). Run it before pushing a
# change to fish, JSON or nvim config: dotup links these straight into every
# machine, where a syntax error breaks the shell, Claude Code or nvim.
#
#   1. fish   fish -n on every tracked .fish file
#   2. json   every tracked .json parses; .devcontainer/ is exempt, as the
#             devcontainer format is JSONC and its comments are deliberate
#   3. nvim   home/.config/nvim starts clean from an empty data dir, as on a
#             new machine: vim.pack installs the locked plugins, no error
#             message is left in v:errmsg, and nvim-pack-lock.json is unchanged
#             (a rewrite means the plugin specs and the lockfile disagree)
#
# Usage: scripts/check_configs.sh      (exit 0 = all passed)
# Needs fish, nvim, git and python3 on PATH (all in nix/flake.nix).

set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

for tool in fish nvim git python3; do
  command -v "$tool" >/dev/null \
    || { echo "check_configs.sh: $tool not on PATH (it comes from nix/flake.nix: run dotup)" >&2; exit 1; }
done

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { log "FAIL $*"; failures=$((failures + 1)); }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. fish ------------------------------------------------------------------

n=0
while IFS= read -r -d '' f; do
  n=$((n + 1))
  fish -n "$f" 2>"$tmp/err" || fail "fish: $f: $(head -n 3 "$tmp/err")"
done < <(git ls-files -z '*.fish')
log "fish: $n files parsed"

# --- 2. json ------------------------------------------------------------------

n=0
while IFS= read -r -d '' f; do
  case "$f" in .devcontainer/*) continue ;; esac
  n=$((n + 1))
  python3 -m json.tool "$f" >/dev/null 2>"$tmp/err" || fail "json: $f: $(tail -n 1 "$tmp/err")"
done < <(git ls-files -z '*.json')
log "json: $n files parsed"

# --- 3. nvim ------------------------------------------------------------------

lock=home/.config/nvim/nvim-pack-lock.json
data="$tmp/nvim"
if ! XDG_CONFIG_HOME="$REPO/home/.config" XDG_DATA_HOME="$data/data" \
  XDG_STATE_HOME="$data/state" XDG_CACHE_HOME="$data/cache" \
  nvim --headless -c 'if v:errmsg != "" | cquit | endif' -c 'qall!' >"$tmp/nvim.log" 2>&1; then
  fail "nvim: startup reported an error: $(grep -v '^vim.pack' "$tmp/nvim.log" | head -n 5)"
elif ! git diff --quiet -- "$lock"; then
  fail "nvim: vim.pack rewrote $lock (plugin specs in core/plugins.lua and the lockfile disagree); git diff it"
else
  log "nvim: config loaded, $(find "$data/data/nvim/site/pack/core/opt" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') locked plugins installed"
fi

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))
