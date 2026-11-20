#!/usr/bin/env bash
#
# machine_name_test.sh -- scripts/machine_name.sh against a throwaway HOME
# and a stand-in `hostname`, and fish's machine_name against the same HOME,
# since both read one file by one rule:
#
#   file "mbp"                       -> mbp           (both)
#   no file, hostname "vm.internal"  -> vm
#   no file, hostname "vm"           -> vm
#   no file                          -> fish: this machine's own host name
#                                       up to its first dot ($hostname is
#                                       read-only there, so no stand-in)
#   file of two words, of two lines,
#     empty                          -> exit 1, the file and its content named
#   no file, hostname prints nothing -> exit 1
#
# fish's half is skipped where fish is not installed: a shell the machine may
# not have, not a dependency of the script.
set -u

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
. "$REPO/scripts/lib/event_log.sh"
event_log_start machine_name_test --no-prune

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"
FILE="$H/.config/dotfiles/machine-name"
mkdir -p "${FILE%/*}" "$WORK/bin"

# hostname prints what $WORK/hostname holds.
printf '#!/bin/sh\ncat "%s/hostname"\n' "$WORK" >"$WORK/bin/hostname"
chmod +x "$WORK/bin/hostname"

name() { HOME="$H" PATH="$WORK/bin:$PATH" "$REPO/scripts/machine_name.sh"; }
fish_name() {
  HOME="$H" fish --no-config -c "source $REPO/home/.config/fish/functions/machine_name.fish; machine_name"
}

expect() { # <what> <wanted>
  local got
  got=$(name 2>&1) && [ "$got" = "$2" ] && pass "$1 -> $2" || fail "$1: wanted '$2', got '$got'"
}

expect_fish() { # <what> <wanted>
  local got
  command -v fish >/dev/null || return 0
  got=$(fish_name 2>&1) && [ "$got" = "$2" ] && pass "fish: $1 -> $2" || fail "fish: $1: wanted '$2', got '$got'"
}

expect_refused() { # <what> <text the message must hold>
  local got rc
  got=$(name 2>&1)
  rc=$?
  [ "$rc" = 1 ] && [[ "$got" == *"$2"* ]] && pass "$1 is refused, and says why" \
    || fail "$1: exit $rc, output '$got'"
}

command -v fish >/dev/null || log "skip fish's machine_name (fish is not installed)"

echo vm.internal >"$WORK/hostname"
echo mbp >"$FILE"
expect "a file holding mbp" mbp
expect_fish "a file holding mbp" mbp

rm "$FILE"
real=$(hostname)
expect_fish "no file, this machine's host name" "${real%%.*}"
expect "no file, hostname vm.internal" vm
echo vm >"$WORK/hostname"
expect "no file, hostname vm" vm

echo "two words" >"$FILE"
expect_refused "a file of two words" "$FILE holds 'two words'"
printf 'mbp\nmore\n' >"$FILE"
expect_refused "a file of two lines" "$FILE holds"
: >"$FILE"
expect_refused "an empty file" "$FILE holds ''"

rm "$FILE"
: >"$WORK/hostname"
expect_refused "a hostname that prints nothing" "hostname prints nothing"

finish
