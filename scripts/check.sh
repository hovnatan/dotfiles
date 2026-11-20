#!/usr/bin/env bash
#
# check.sh -- every check CI runs on this repo, in one place. The CI
# workflows call it, and the pre-push hook (scripts/git-hooks/) runs its
# lint, a few seconds, before a push; the flake check and the tests are
# CI's, or run by hand here.
#
#   check      what                                            CI workflow
#   shell      shellcheck -S warning and shfmt -d (style in    shellcheck.yml
#              .editorconfig) on every tracked .sh and git
#              hook, and no bare GNU `timeout`
#   lua        stylua --check on every tracked .lua            lua.yml
#   python     ruff check and ruff format --check on every     python.yml
#              tracked .py, rules in home/.config/ruff
#   typescript biome check (lint and format; rules and the     typescript.yml
#              files, .ts and .js, in biome.jsonc)
#   configs    scripts/check_configs.sh: fish parse and        configs.yml
#              layout, JSON, nvim startup
#   markdown   markdownlint-cli2 on every tracked .md          markdown.yml
#   yaml       yamlfmt -lint and yamllint --strict on every    yaml.yml
#              tracked .yml/.yaml, actionlint on workflows
#   nix        scripts/check_nix_flake.sh (nix.yml adds        nix.yml
#              --build on Linux)
#   tests      scripts/tests/*_test.sh, each a check of its    tests.yml
#              own (test:<name>)
#
# Usage:
#   scripts/check.sh                       every check
#   scripts/check.sh lua tests             just those
#   scripts/check.sh lint                  shell to yaml in the table: all
#                                          but nix and the tests (the
#                                          pre-push hook's mode)
#   --list first (before the rest)         print the checks it would run,
#                                          one a line, and run none
#
# A test that runs on one OS only says so near its top (`uname`'s name), and
# is skipped on another, which is logged:
#   # check.sh runs-on: Linux
#
# Output: a UTC-stamped line as each check starts and ends, and a failing
# check's whole output. Exit 0 = every selected check passed.

set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
usage() {
  echo "usage: $0 [--list] [lint|shell|lua|python|typescript|configs|markdown|yaml|nix|tests ...]" >&2
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
# have no .sh, as git runs them by their bare names. Vendored code
# (home/.config/tmux/vendor/, each pinned by its .upstream) is left out: it
# stays byte-for-byte upstream's, in upstream's style.
shell_files() {
  git ls-files -z '*.sh' 'scripts/git-hooks/*' ':(exclude)home/.config/tmux/vendor/**'
}

# Fix a shfmt failure with:  scripts/check.sh's shell_files | xargs -0 shfmt -w
check_shell() {
  need shellcheck shfmt || return 1
  shell_files | xargs -0 shellcheck -S warning || return 1

  # No style flags: shfmt then reads .editorconfig, and any flag would make
  # it ignore that file. -d prints the diff a fix would apply.
  shell_files | xargs -0 shfmt -d || return 1

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

# python_files: every tracked .py, NUL-separated, but vendored code (as in
# shell_files).
python_files() {
  git ls-files -z '*.py' ':(exclude)home/.config/tmux/vendor/**'
}

# The config is named, not found: ruff would otherwise read ~/.config/ruff,
# which CI has none of. It is the same file once installed.
# Fix a format failure with:  scripts/check.sh's python_files | xargs -0 ruff format
check_python() {
  need ruff || return 1
  local config=home/.config/ruff/pyproject.toml
  python_files | xargs -0 ruff check --config "$config" || return 1
  python_files | xargs -0 ruff format --check --config "$config"
}

# Lint, import order and format in one pass, a warning failing as an error
# does. No file list: biome.jsonc names the files, as markdownlint's config
# does, and git's ignore rules apply. The types are not checked here: tsc needs what Claude Code writes
# into a mod it has loaded, so that is scripts/tests/claude_mods_test.sh's.
# Fix a failure with:  biome check --write
check_typescript() {
  need biome || return 1
  biome check --error-on-warnings
}

check_configs() { scripts/check_configs.sh; }

# Add --fix for the spacing rules, then read its diff: it rewrites `|` in
# table cells, `*` and `_` in math, and URLs inside shell commands wrongly.
check_markdown() {
  need markdownlint-cli2 || return 1
  markdownlint-cli2
}

# yaml_files: every tracked YAML file, NUL-separated.
yaml_files() { git ls-files -z '*.yml' '*.yaml'; }

# Fix a yamlfmt failure with:  git ls-files -z '*.yml' '*.yaml' | xargs -0 yamlfmt
# yamlfmt owns the layout (.yamlfmt.yaml), yamllint the rest (.yamllint.yaml):
# duplicate keys, line length. actionlint reads .github/workflows/ itself and
# runs shellcheck on each `run:` block, skipping them silently when shellcheck
# is missing, hence the need on it.
check_yaml() {
  need yamlfmt yamllint actionlint shellcheck || return 1
  yaml_files | xargs -0 yamlfmt -lint || return 1
  yaml_files | xargs -0 yamllint --strict || return 1
  actionlint
}

check_nix() { scripts/check_nix_flake.sh; }

# test_os <test>: the OS of the test's `# check.sh runs-on:` line, if any.
test_os() { sed -n 's/^# check\.sh runs-on: //p' "$1" | head -n 1; }

# test_name <test>: scripts/tests/tmux_hooks_test.sh -> tmux_hooks
test_name() {
  local n=${1##*/}
  echo "${n%_test.sh}"
}

# --- what to run --------------------------------------------------------------

checks=() # shell lua python typescript configs markdown yaml nix test:<name> ...
lint=(shell lua python typescript configs markdown yaml)
add_all_tests() {
  local t
  for t in scripts/tests/*_test.sh; do checks+=("test:$(test_name "$t")"); done
}

list=0
if [ "${1:-}" = --list ]; then
  list=1
  shift
fi

if [ $# -eq 0 ]; then
  checks=("${lint[@]}" nix)
  add_all_tests
else
  for c; do
    case "$c" in
      shell | lua | python | typescript | configs | markdown | yaml | nix) checks+=("$c") ;;
      lint) checks+=("${lint[@]}") ;;
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
      os=$(test_os "$t")
      if [ -n "$os" ] && [ "$os" != "$(uname)" ]; then
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
