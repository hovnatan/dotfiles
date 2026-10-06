#!/usr/bin/env bash
# check.sh covers: scripts/check.sh scripts/git-hooks/* scripts/lib/*
#
# check_test.sh -- checks for scripts/check.sh's choice of checks and for
# the pre-push hook (scripts/git-hooks/pre-push) that runs it. About 2 s.
#
#   selection    check.sh --list: what --changed picks for a path, read
#                against this repo's real tests and their covers lines
#     a tmux script      -> lint, test:appearance, test:tmux_hooks
#     README.md          -> lint only
#     nix/flake.nix      -> lint and nix
#     nix/flake.lock     -> lint, nix and every test
#     a test's own .lua  -> that test
#     named / none       -> just those / every check
#
#   hook         a throwaway clone whose scripts/check.sh is a stub that
#                logs its arguments and fails when the pushed commit holds
#                a file named FAIL; pushes go to a throwaway bare remote
#     pass        the push lands; the stub saw --changed and the paths of
#                the new commits only
#     fail        the push is stopped and the remote is left as it was
#     committed   an uncommitted FAIL in the clone does not stop a clean
#                 commit: the commit is checked, not the working tree
#     worktrees   none left behind
#     log         each push is noted in the day's event log
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() { log "FAIL $*"; failures=$((failures + 1)); }
cleanup() {
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# --- selection ----------------------------------------------------------------

# picks <expected, space-separated> <check.sh args...>
picks() {
  local want=$1 got
  shift
  got=$("$REPO/scripts/check.sh" --list "$@" | tr '\n' ' ')
  got=${got% }
  if [ "$got" = "$want" ]; then
    pass "selection: $* -> $got"
  else
    fail "selection: $*: want '$want', got '$got'"
  fi
}

lint="shell lua configs markdown"
all_tests=$(for t in "$REPO"/scripts/tests/*_test.sh; do
  n=${t##*/}
  printf 'test:%s ' "${n%_test.sh}"
done)
all_tests=${all_tests% }

picks "$lint test:appearance test:tmux_hooks" --changed home/.config/tmux/retitle.sh
picks "$lint" --changed README.md
picks "$lint nix" --changed nix/flake.nix
picks "$lint nix $all_tests" --changed nix/flake.lock
picks "$lint test:ssh_command" --changed scripts/tests/ssh_command_test.lua
picks "$lint" --changed
picks "lua $all_tests" lua tests
picks "$lint nix $all_tests"

# --- hook ---------------------------------------------------------------------

H="$WORK/home"
CLONE="$WORK/clone"
REMOTE="$WORK/remote.git"
mkdir -p "$H" "$CLONE/scripts/lib" "$CLONE/scripts/git-hooks"

# env -i keeps the hook from the caller's git environment and HOME: its
# event log goes to $H/.dotfiles/.logs.
g() { env -i HOME="$H" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 git -C "$CLONE" "$@"; }

cp "$REPO/scripts/lib/event_log.sh" "$CLONE/scripts/lib/"
cp "$REPO/scripts/prune_logs.sh" "$CLONE/scripts/"
cp "$REPO/scripts/git-hooks/pre-push" "$CLONE/scripts/git-hooks/"
cat > "$CLONE/scripts/check.sh" << EOF
#!/usr/bin/env bash
echo "\$*" >> "$WORK/check_args"
[ ! -e FAIL ]
EOF
chmod +x "$CLONE/scripts/check.sh"

git init -q --bare "$REMOTE"
g init -q -b main
g config user.email test@example.com
g config user.name test
g config core.hooksPath scripts/git-hooks
g add -A
g commit -qm base
g remote add origin "$REMOTE"
g push -q --no-verify origin main 2>/dev/null

# pass: one new commit with one new file
echo a > "$CLONE/a.txt"
g add a.txt
g commit -qm a
: > "$WORK/check_args"
if g push -q origin main > "$WORK/out" 2>&1 \
  && [ "$(git -C "$REMOTE" rev-parse main)" = "$(g rev-parse main)" ]; then
  if [ "$(cat "$WORK/check_args")" = "--changed a.txt" ]; then
    pass "hook pass: the push landed; check.sh got --changed a.txt"
  else
    fail "hook pass: check.sh got '$(cat "$WORK/check_args")'"
  fi
else
  fail "hook pass: push failed: $(cat "$WORK/out")"
fi

# fail: a commit holding FAIL
before=$(git -C "$REMOTE" rev-parse main)
touch "$CLONE/FAIL"
g add FAIL
g commit -qm fail
if g push -q origin main > "$WORK/out" 2>&1; then
  fail "hook fail: the push went through"
elif [ "$(git -C "$REMOTE" rev-parse main)" != "$before" ]; then
  fail "hook fail: the remote moved"
elif grep -q "push stopped" "$WORK/out"; then
  pass "hook fail: the push was stopped, the remote left as it was"
else
  fail "hook fail: no 'push stopped' line: $(cat "$WORK/out")"
fi

# committed: drop the FAIL commit, keep FAIL as an untracked file
g reset -q --hard HEAD~1
touch "$CLONE/FAIL"
echo b > "$CLONE/b.txt"
g add b.txt
g commit -qm b
if g push -q origin main > "$WORK/out" 2>&1; then
  pass "hook committed: an uncommitted FAIL did not stop a clean commit"
else
  fail "hook committed: the push was stopped: $(cat "$WORK/out")"
fi
rm -f "$CLONE/FAIL"

n=$(g worktree list | wc -l | tr -d ' ')
if [ "$n" -eq 1 ]; then
  pass "hook worktrees: none left behind"
else
  fail "hook worktrees: $(g worktree list)"
fi

events=$(cat "$H"/.dotfiles/.logs/*_git_pre_push/events.log 2>/dev/null)
if [ "$(grep -c 'checks passed' <<< "$events")" -eq 2 ] \
  && [ "$(grep -c 'checks FAILED' <<< "$events")" -eq 1 ]; then
  pass "hook log: two passes and one failure noted"
else
  fail "hook log: $events"
fi

log "$failures failure(s)"
[ "$failures" -eq 0 ]
