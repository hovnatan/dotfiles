#!/usr/bin/env bash
#
# check.sh -- every check CI runs on this repo, in one place. The CI
# workflows call it, and so does the pre-push hook (scripts/git-hooks/), so
# a push is checked on the machine before CI sees it.
#
#   check      what                                            CI workflow
#   shell      shellcheck -S warning on every tracked .sh      shellcheck.yml
#              and git hook, and no bare GNU `timeout`
#   lua        stylua --check on every tracked .lua            lua.yml
#   configs    scripts/check_configs.sh: fish parse and        configs.yml
#              layout, JSON, nvim startup
#   markdown   markdownlint-cli2 on every tracked .md          markdown.yml
#   nix        scripts/check_nix_flake.sh (nix.yml adds        nix.yml
#              --build on Linux)
#   tests      scripts/tests/*_test.sh, each a check of its    tests.yml
#              own (test:<name>)
#
# Usage:
#   scripts/check.sh                       every check
#   scripts/check.sh lua tests             just those
#   scripts/check.sh --changed <path>...   what a change to those paths
#                                          needs (the pre-push hook's mode)
#   --list first (before the rest)         print the checks it would run,
#                                          one a line, and run none
#
# --changed picks:
#   shell lua configs markdown   always: a few seconds over the whole repo
#   nix                          a path under nix/, or check_nix_flake.sh
#   test:<name>                  a path its `# check.sh covers:` line names,
#                                or the test's own files; every test when
#                                check.sh, tests.yml or nix/flake.lock (the
#                                tools the tests drive) changed
#
#   e.g. --changed home/.config/tmux/retitle.sh README.md
#        -> shell lua configs markdown test:appearance test:tmux_hooks
#
# Each test declares, near its top (bash patterns; `*` also spans `/`):
#   # check.sh covers: scripts/prune_logs.sh scripts/lib/*
#   # check.sh runs-on: Linux        (optional: `uname`; else any OS)
# A test missing its covers line fails: it would otherwise never run before
# a push. One whose runs-on is another OS is skipped, and says so.
#
# Output: a UTC-stamped line as each check starts and ends, and a failing
# check's whole output. Exit 0 = every selected check passed.

set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
usage() {
  echo "usage: $0 [shell|lua|configs|markdown|nix|tests ...] | --changed <path>..." >&2
  exit 2
}

# need <tool>...: fail the running check, naming what is missing.
need() {
  local tool
  for tool; do
    command -v "$tool" >/dev/null \
      || {
        echo "$tool not on PATH (it comes from nix/flake.nix: run dotup)"
        return 1
      }
  done
}

# --- the checks ---------------------------------------------------------------

# shell_files: every tracked shell script, NUL-separated. The git hooks
# have no .sh, as git runs them by their bare names.
shell_files() { git ls-files -z '*.sh' 'scripts/git-hooks/*'; }

check_shell() {
  need shellcheck || return 1
  shell_files | xargs -0 shellcheck -S warning || return 1

  # GNU-only commands shellcheck cannot see (AGENTS.md: scripts run on macOS
  # too). `timeout` is coreutils; macOS has none, so a bare call exits 127
  # there. Flags an invocation with a duration (`timeout 30 ssh`) outside
  # comments; a guarded use that stores it in a variable after
  # `command -v timeout` (home/.claude/statusline-command.sh) passes.
  local pat='(^|[;&|(`]|[[:space:]])timeout[[:space:]]+[0-9]'
  if shell_files | xargs -0 grep -nE "$pat" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; then
    echo "bare 'timeout' is GNU-only; macOS lacks it. Guard with 'command -v timeout' or drop it."
    return 1
  fi
}

# Fix a failure with:  git ls-files -z '*.lua' | xargs -0 stylua
check_lua() {
  need stylua || return 1
  git ls-files -z '*.lua' | xargs -0 stylua --check
}

check_configs() { scripts/check_configs.sh; }

# Add --fix for the spacing rules, then read its diff: it rewrites `|` in
# table cells, `*` and `_` in math, and URLs inside shell commands wrongly.
check_markdown() {
  need markdownlint-cli2 || return 1
  markdownlint-cli2
}

check_nix() { scripts/check_nix_flake.sh; }

# test_meta <test> <key>: the value of the test's `# check.sh <key>:` line.
test_meta() { sed -n "s/^# check\.sh $2: //p" "$1" | head -n 1; }

# test_name <test>: scripts/tests/tmux_hooks_test.sh -> tmux_hooks
test_name() {
  local n=${1##*/}
  echo "${n%_test.sh}"
}

# test_covers <test> <path>...: whether a change to any path needs the test.
test_covers() {
  local t=$1 p g
  shift
  local -a globs
  read -ra globs <<<"$(test_meta "$t" covers)"
  for p; do
    case "$p" in
      "${t%_test.sh}"_test.* | scripts/check.sh | .github/workflows/tests.yml | nix/flake.lock) return 0 ;;
    esac
    for g in "${globs[@]}"; do
      # shellcheck disable=SC2053 # $g is a pattern on purpose
      [[ $p == $g ]] && return 0
    done
  done
  return 1
}

# --- what to run --------------------------------------------------------------

checks=() # shell lua configs markdown nix test:<name> ...
add_all_tests() {
  local t
  for t in scripts/tests/*_test.sh; do checks+=("test:$(test_name "$t")"); done
}

list=0
if [ "${1:-}" = --list ]; then
  list=1
  shift
fi

if [ "${1:-}" = --changed ]; then
  shift
  checks=(shell lua configs markdown)
  for p; do
    case "$p" in nix/* | scripts/check_nix_flake.sh)
      checks+=(nix)
      break
      ;;
    esac
  done
  # A test without its covers line is picked too, to fail on that below.
  for t in scripts/tests/*_test.sh; do
    if [ -z "$(test_meta "$t" covers)" ] || test_covers "$t" "$@"; then
      checks+=("test:$(test_name "$t")")
    fi
  done
elif [ $# -eq 0 ]; then
  checks=(shell lua configs markdown nix)
  add_all_tests
else
  for c; do
    case "$c" in
      shell | lua | configs | markdown | nix) checks+=("$c") ;;
      tests) add_all_tests ;;
      *) usage ;;
    esac
  done
fi

if [ "$list" -eq 1 ]; then
  printf '%s\n' "${checks[@]}"
  exit 0
fi

# --- run ----------------------------------------------------------------------

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=()
passed=0

# run <label> <command...>: one check, its output kept and shown on failure.
run() {
  local label=$1 start=$SECONDS
  shift
  log "start $label"
  if "$@" >"$tmp/out" 2>&1; then
    log "PASS  $label ($((SECONDS - start)) s)"
    passed=$((passed + 1))
  else
    log "FAIL  $label ($((SECONDS - start)) s):"
    sed 's/^/    /' "$tmp/out"
    failed+=("$label")
  fi
}

log "checks: ${checks[*]}"
for c in "${checks[@]}"; do
  case "$c" in
    test:*)
      t=scripts/tests/${c#test:}_test.sh
      os=$(test_meta "$t" runs-on)
      if [ -z "$(test_meta "$t" covers)" ]; then
        log "FAIL  $c: $t has no '# check.sh covers:' line (see scripts/check.sh)"
        failed+=("$c")
      elif [ -n "$os" ] && [ "$os" != "$(uname)" ]; then
        log "skip  $c (runs on $os only)"
      else
        run "$c" "$t"
      fi
      ;;
    *) run "$c" "check_$c" ;;
  esac
done

if [ ${#failed[@]} -eq 0 ]; then
  log "all $passed checks passed"
else
  log "${#failed[@]} failed: ${failed[*]}"
  exit 1
fi
