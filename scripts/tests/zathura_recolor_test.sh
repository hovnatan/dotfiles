#!/usr/bin/env bash
#
# zathura_recolor_test.sh -- end-to-end checks for scripts/zathura_recolor.sh,
# zathura's r key. Runs the script for real in a throwaway HOME; the window
# is a `sleep`, and dbus-send is lib.sh's stand-in, so no window opens. A few
# seconds.
#
#   plain            the first r: the theme's plain settings, then
#                    recolouring off, and the window noted; in the dark
#                    theme, the dark one's
#   recoloured       the second: the theme's settings, then recolouring on,
#                    and the note gone
#   another process  a note with another start time is some earlier process
#                    with the pid: r turns the window plain
#   closed           the note of a window since closed is removed
#   refused          a window answering false fails the run, with no note
#   arguments        none, and a name that is no zathura window, fail
#   colours missing  no plain file for the theme, or a theme that is a file
#                    and not appearance.sh's link, fails with nothing sent
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
SCRIPT="$REPO/scripts/zathura_recolor.sh"
WORK=$(mktemp -d)
H="$WORK/home"
Z="$H/.config/zathura"
NOTES="$H/.cache/zathura_plain"
OTHER_START="Thu Jan  1 00:00:00 1970"

cleanup() {
  [ -n "${win:-}" ] && kill "$win" 2>/dev/null
  drop_work
}
trap cleanup EXIT

mkdir -p "$Z" "$H/bin"
cp "$REPO"/home/.config/zathura/gruvbox-* "$Z/"
ln -s gruvbox-light "$Z/theme"
dbus_send_stub "$H/bin"

sleep 60 &
win=$!
name="org.pwmt.zathura.PID-$win"

# One r, with the arguments given.
run() {
  : >"$WORK/calls"
  env -i HOME="$H" PATH="$H/bin:/usr/bin:/bin" CALLS="$WORK/calls" ANSWER="${ANSWER:-true}" \
    "$SCRIPT" "$@" >"$WORK/out" 2>&1
}
# sent <file> <command>: the window got that file's set lines, then the command
sent() {
  {
    sed -n "s/^set /$name | string:set /p" "$Z/$1"
    echo "$name | string:$2"
  } | diff - "$WORK/calls" >"$WORK/diff"
}
shown() { echo "exit $?, sent: $(tr '\n' ';' <"$WORK/calls") out: $(cat "$WORK/out")"; }

if run "$name" && sent gruvbox-light-plain 'set recolor false' && [ -f "$NOTES/$win" ]; then
  pass "plain: the light theme's plain settings, recolouring off, the window noted"
else
  fail "plain: $(shown)"
fi

if run "$name" && sent gruvbox-light 'set recolor true' && [ ! -e "$NOTES/$win" ]; then
  pass "recoloured: the theme's settings, recolouring on, the note gone"
else
  fail "recoloured: $(shown)"
fi

mkdir -p "$NOTES"
echo "$OTHER_START" >"$NOTES/$win"
if run "$name" && sent gruvbox-light-plain 'set recolor false' \
  && [ "$(cat "$NOTES/$win")" = "$(ps -o lstart= -p "$win")" ]; then
  pass "another process: a note with another start time is not this window's"
else
  fail "another process: $(shown)"
fi

sleep 0 &
closed=$!
wait "$closed"
echo "$OTHER_START" >"$NOTES/$closed"
if run "$name" && [ ! -e "$NOTES/$closed" ] && [ ! -e "$NOTES/$win" ]; then
  pass "closed: the note of a window since closed is removed"
else
  fail "closed: notes left: $(ls "$NOTES"), $(shown)"
fi

ln -sfn gruvbox-dark "$Z/theme"
if run "$name" && sent gruvbox-dark-plain 'set recolor false' && [ -f "$NOTES/$win" ]; then
  pass "plain: in the dark theme, its plain settings ($(grep '^set ' "$Z/gruvbox-dark-plain"))"
else
  fail "plain, dark: $(shown)"
fi
ln -sfn gruvbox-light "$Z/theme"
run "$name" || fail "recoloured again: $(shown)"

if ANSWER=false run "$name"; then
  fail "refused: a window answering false passed"
elif grep -q "$name refused 'set default-bg" "$WORK/out" && [ ! -e "$NOTES/$win" ]; then
  pass "refused: a window answering false fails the run, with no note"
else
  fail "refused: $(shown)"
fi

for arg in "" "org.pwmt.zathura.PID-12x"; do
  if run $arg; then
    fail "arguments: '$arg' was taken"
  elif grep -q 'usage: zathura_recolor.sh' "$WORK/out" && [ ! -s "$WORK/calls" ]; then
    pass "arguments: '$arg' refused, nothing sent"
  else
    fail "arguments: '$arg': $(shown)"
  fi
done

rm "$Z/gruvbox-light-plain"
if run "$name"; then
  fail "colours missing: no plain file passed"
elif grep -q 'gruvbox-light-plain missing' "$WORK/out" && [ ! -s "$WORK/calls" ] && [ ! -e "$NOTES/$win" ]; then
  pass "colours missing: no plain file for the theme fails, nothing sent, no note"
else
  fail "colours missing: no plain file: $(shown)"
fi
rm "$Z/theme"
cp "$Z/gruvbox-dark" "$Z/theme"
if run "$name"; then
  fail "colours missing: a theme that is a file passed"
elif grep -q 'theme is not a link' "$WORK/out" && [ ! -s "$WORK/calls" ] && [ ! -e "$NOTES/$win" ]; then
  pass "colours missing: a theme that is a file fails, nothing sent, no note"
else
  fail "colours missing: a theme that is a file: $(shown)"
fi

finish
