#!/usr/bin/env bash
# check.sh covers: home/.claude/git-guard.sh
#
# git_guard_test.sh -- checks for home/.claude/git-guard.sh: each command below is
# fed to the hook as a PreToolUse payload, the way Claude Code sends it, and
# the hook must ask (print a permissionDecision "ask") for every destructive
# push and stay silent for everything else. Needs jq; about 1 s.
#
#   payload {"tool_input":{"command":<cmd>}} -> git-guard.sh -> "ask" | nothing
#
# Plus the fail-closed case: with no jq on PATH, a git command still gets
# the prompt instead of passing unseen.
#
# Usage: scripts/tests/git_guard_test.sh   (exit 0 = all passed)

set -uo pipefail

command -v jq >/dev/null || {
  echo "git_guard_test.sh: jq not on PATH" >&2
  exit 1
}

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
HOOK="$ROOT/home/.claude/git-guard.sh"

failures=0
n=0
log() { printf '%s %02d %s\n' "$(date -u +%H:%M:%S)" "$n" "$*"; }

# decision <command> [PATH]: what the hook decides for that Bash command.
decision() {
  local out
  out=$(jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | env PATH="${2:-$PATH}" "$HOOK")
  if [ -z "$out" ]; then
    echo allow
  else
    jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"
  fi
}

expect() { # expect ask|allow <command> [PATH]
  n=$((n + 1))
  local got
  got=$(decision "$2" "${3:-$PATH}")
  if [ "$got" = "$1" ]; then
    log "PASS $1   $2"
  else
    log "FAIL want $1, got $got   $2"
    failures=$((failures + 1))
  fi
}

# --- destructive pushes: every spelling must ask ---------------------------
expect ask 'git push --force'
expect ask 'git push -f origin main'
expect ask 'git push -fu origin main'
expect ask 'git push --force-with-lease origin main'
expect ask 'git push --force-with-lease=main origin main'
expect ask 'git push --mirror backup'
expect ask 'git push --delete origin old'
expect ask 'git push -d origin old'
expect ask 'git push origin +main'
expect ask 'git push origin :old'
expect ask 'git -C ../repo push -f'
expect ask 'git -c push.default=current push --force'
expect ask 'cd repo && git push -f'
expect ask 'git status; git push --force'
# The spellings the first version let through:
expect ask 'echo "$(git push --force origin main)"'
expect ask 'echo `git push --force origin main`'
expect ask 'bash -c "git push --force origin main"'
expect ask "sh -c 'git push -f'"
expect ask '/usr/bin/git push --force origin main'
expect ask 'git push origin "+main"'
expect ask "git push origin '+main'"
expect ask '\git push -f'
expect ask 'sudo git push -f'
expect ask 'env GIT_TRACE=1 git push --force'
expect ask '(cd repo && git push -f)'

# --- everything else runs unprompted ---------------------------------------
expect allow 'git push'
expect allow 'git push origin main'
expect allow 'git push -u origin feature'
expect allow 'git push origin HEAD:refs/heads/feature'
expect allow 'git push --dry-run origin main'
expect allow 'git status'
expect allow 'git commit -m "push -f is never ok"'
expect allow 'git log --format=%d -- push'
expect allow 'git fetch origin +refs/heads/*:refs/remotes/origin/*'
expect allow 'ls -la'

# --- fail closed: no jq on PATH -------------------------------------------
# A PATH with bash and the coreutils but no jq.
nojq=$(mktemp -d)
for c in bash env cat; do ln -s "$(command -v "$c")" "$nojq/$c"; done
n=$((n + 1))
out=$(jq -cn '{tool_input:{command:"git push --force"}}' | env PATH="$nojq" bash "$HOOK")
if grep -q '"permissionDecision":"ask"' <<<"$out"; then
  log "PASS ask   (no jq on PATH) git push --force"
else
  log "FAIL want ask, got '${out}'   (no jq on PATH) git push --force"
  failures=$((failures + 1))
fi
rm -rf "$nojq"

log "$([ "$failures" -eq 0 ] && echo "all $n checks passed" || echo "$failures of $n check(s) failed")"
exit $((failures > 0))
