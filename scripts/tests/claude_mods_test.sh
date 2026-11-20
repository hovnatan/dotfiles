#!/usr/bin/env bash
# check.sh covers: home/.claude/mods/* home/.claude/settings.json
#
# claude_mods_test.sh -- the mods Claude Code loads from this repo
# (home/.claude/mods/<mod>/), checked from the outside in:
#
#   settings.json       CLAUDE_CODE_PLUGIN_DIRS names every mod folder in the
#                       repo, and every folder it names is one: a mod left
#                       out, or a path gone stale, loads nothing in silence
#   per mod:
#     claude plugin validate   the manifest, the module and its state contract
#                              load as the engine reads them
#     claude plugin test       hooks/register.test.ts: what the mod does, case
#                              by case (the header of its register.ts)
#     tsc                      the module and its tests against the types of
#                              the installed Claude Code's API, which claude
#                              writes into .claude-plugin/types/ (git ignores
#                              them) of each mod it loads from ~/.dotfiles
#
# The three per-mod checks are skipped where claude is not installed (CI): a
# mod runs nowhere claude does not, and its API is the installed build's, so
# only a machine with claude can say whether a mod still fits it. Lint and
# format need no claude: scripts/check.sh's `typescript` check.
#
# Not here, each with a shell test of its own: the session-done mod's
# script, loaded-check.sh (scripts/tests/session_done_loaded_check_test.sh);
# the rule its push asks tmux by, scripts/tmux_watched.sh
# (scripts/tests/tmux_watched_test.sh); and scripts/event_log_note.sh, the
# mods' way to the event log (scripts/tests/prune_logs_test.sh).
#
# Needs jq, and tsc beside claude (nix/flake.nix); about 2 s.
# Usage: scripts/tests/claude_mods_test.sh (exit 0 = all passed)
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"
event_log_start claude_mods_test --no-prune

command -v jq >/dev/null || {
  log "FAIL jq is not on PATH; this test reads settings.json with it"
  exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0
# log prints each line as well as recording it (scripts/lib/event_log.sh).
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}

# --- settings.json and the mods folder name the same mods --------------------
# "~/.dotfiles/home/.claude/mods/session-rename:~/.dotfiles/home/.claude/mods/session-done"
# -> each folder, as a path in this checkout, holds a manifest; and each
# folder of home/.claude/mods/ is in the list.
dirs=$(jq -r '.env.CLAUDE_CODE_PLUGIN_DIRS // ""' "$REPO/home/.claude/settings.json")
IFS=: read -ra named <<<"$dirs"
for d in "${named[@]}"; do
  here=${d/#"~/.dotfiles"/$REPO}
  [ -f "$here/.claude-plugin/plugin.json" ] && pass "$d, named in CLAUDE_CODE_PLUGIN_DIRS, is a mod in this repo" \
    || fail "$d, named in CLAUDE_CODE_PLUGIN_DIRS, has no .claude-plugin/plugin.json at $here"
done
mods=()
for m in "$REPO"/home/.claude/mods/*/; do
  m=${m%/}
  mods+=("$m")
  [[ ":$dirs:" == *":~/.dotfiles/home/.claude/mods/${m##*/}:"* ]] && pass "settings.json loads ${m##*/}" \
    || fail "home/.claude/mods/${m##*/} is not in settings.json's CLAUDE_CODE_PLUGIN_DIRS ('$dirs'): claude never loads it"
done
[ "${#mods[@]}" -gt 0 ] || fail "no mod under $REPO/home/.claude/mods"

# --- claude's own checks of each mod, and the types --------------------------
if ! command -v claude >/dev/null; then
  log "skip claude plugin validate, claude plugin test and tsc (claude is not installed)"
else
  command -v tsc >/dev/null || fail "tsc is not on PATH (it comes from nix/flake.nix: run dotup)"
  for m in "${mods[@]}"; do
    name=${m##*/}
    out=$(claude plugin validate "$m" 2>&1) && pass "$name: claude plugin validate" \
      || fail "$name: claude plugin validate: $out"
    out=$(claude plugin test "$m" 2>&1) && pass "$name: claude plugin test: $(grep -E '^ *[0-9]+ pass' <<<"$out" | tr -s ' ')" \
      || fail "$name: claude plugin test: $out"

    # The types are the installed claude's, written where it loads the mod
    # from (the path settings.json names), not into this checkout: a
    # worktree or a second clone has none.
    # So this checkout's sources are checked against those types:
    #   $WORK/<mod>.tsconfig.json: extends <where claude loads it>/.claude-plugin/types/tsconfig.json,
    #                              include <this checkout's mod>/hooks and /types
    types="$HOME/.dotfiles/home/.claude/mods/$name/.claude-plugin/types/tsconfig.json"
    if [ ! -f "$types" ]; then
      fail "$name: no $types to type-check against; start claude once, which loads the mod and writes its types"
    else
      printf '{ "extends": "%s", "include": ["%s/hooks", "%s/types"] }\n' "$types" "$m" "$m" >"$WORK/$name.tsconfig.json"
      out=$(tsc -p "$WORK/$name.tsconfig.json" --noEmit 2>&1) && pass "$name: tsc" \
        || fail "$name: tsc: $out"
    fi
  done
fi

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))
