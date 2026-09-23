#!/usr/bin/env bash
#
# check_nix_flake.sh -- the checks CI runs on nix/ (.github/workflows/nix.yml).
# Run it before pushing a change to nix/flake.nix or nix/flake.lock: `dotup`
# applies that flake on every machine, so a mistake here breaks all of them.
#
#   1. evaluate    every system's package set (nix flake check --all-systems),
#                  failing on any evaluation warning (deprecated attributes)
#   2. substitute  every system's set must come from cache.nixos.org, apart
#                  from the known trivial local builds (LOCAL_OK): anything
#                  else in `nix build --dry-run`'s "will be built" list means
#                  a Mac or VM would compile it at dotup time (a lock bump
#                  outrunning the cache, or an override that changes a hash)
#   3. build       (--build) this machine's set: buildEnv only notices two
#                  packages installing the same file when it actually builds
#
# Usage: scripts/check_nix_flake.sh [--build]      (exit 0 = all passed)

set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
FLAKE="path:$REPO/nix"
SYSTEMS=(x86_64-linux aarch64-linux aarch64-darwin)
# Local builds that are allowed at dotup time. Wrappers and symlink farms,
# never compiles: the buildEnv itself and its builder script,
# hunspell.withDicts, nodejs (a wrapper around the substituted nodejs-slim)
# and azure-cli-extensions (the extension dir). One real build, accepted on
# purpose: azure-cli.withExtensions re-runs the azure-cli Python package build
# and its `az self-test`, ~80s on an M-series Mac, no C compiles
# (2026-09-23, nix/flake.nix). And terraform, unfree so never in the cache: a
# Go build of ~4.5 min on an 8-CPU VM, after each lock bump (2026-09-23).
# Extend only with a derivation you have checked is trivial, or say here what
# it costs.
LOCAL_OK='^(dotfiles-packages|builder\.pl|hunspell-with-dicts-[0-9.]+|nodejs-[0-9.]+|azure-cli-extensions|python3\.[0-9]+-azure-cli-[0-9.]+|terraform-[0-9.]+)$'

build=0
case "${1:-}" in
  --build) build=1 ;;
  "") ;;
  *) echo "usage: $0 [--build]" >&2; exit 2 ;;
esac

command -v nix >/dev/null || { echo "check_nix_flake.sh: nix not on PATH (see README.md \"Nix packages\")" >&2; exit 1; }

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { log "FAIL $*"; failures=$((failures + 1)); }
err=$(mktemp)
trap 'rm -f "$err"' EXIT

# --- 1. evaluate --------------------------------------------------------------

log "evaluate: nix flake check --all-systems --no-build"
if ! nix flake check --all-systems --no-build "$FLAKE" 2>"$err"; then
  cat "$err" >&2
  fail "flake check"
elif grep -i 'warning' "$err"; then
  fail "evaluation warnings (above): fix them before they turn into errors"
else
  log "PASS evaluate: ${SYSTEMS[*]}"
fi

# --- 2. substitute ------------------------------------------------------------

for system in "${SYSTEMS[@]}"; do
  if ! nix build --dry-run --no-link "$FLAKE#packages.$system.default" 2>"$err"; then
    cat "$err" >&2
    fail "$system: dry-run build"
    continue
  fi
  # "these N derivations will be built:" then one indented .drv per line;
  # reduced to derivation names (the part after the hash, without .drv).
  # The `;` before `}` is for BSD sed, which rejects the block without it; a
  # sed error must fail the check, or an empty list reads as "all cached".
  if ! local_builds=$(sed -n '/will be built:$/,/^[^ ]/{s|^  /nix/store/[a-z0-9]*-\(.*\)\.drv$|\1|p;}' "$err"); then
    fail "$system: could not parse the dry-run's 'will be built' list"
    continue
  fi
  unexpected=$(grep -vE "$LOCAL_OK" <<<"$local_builds" | grep -v '^$')
  fetched=$(grep -o 'these [0-9]* paths will be fetched[^)]*)' "$err")
  if [ -n "$unexpected" ]; then
    fail "$system: would compile locally (not in cache.nixos.org): $(tr '\n' ' ' <<<"$unexpected")"
  else
    log "PASS substitute $system: ${fetched:-nothing to fetch}; local: $(tr '\n' ' ' <<<"$local_builds")"
  fi
done

# --- 3. build -----------------------------------------------------------------

if [ "$build" -eq 1 ]; then
  system=$(nix eval --impure --raw --expr builtins.currentSystem)
  log "build: packages.$system.default"
  if out=$(nix build --no-link --print-out-paths "$FLAKE#packages.$system.default" 2>"$err"); then
    log "PASS build $system: $out"
  else
    cat "$err" >&2
    fail "build $system (two packages installing the same file show as 'conflicting subpath' above)"
  fi
fi

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))
