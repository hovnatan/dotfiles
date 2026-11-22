#!/usr/bin/env bash
#
# tmux_claude_fullscreen_test.sh -- in a full-screen Claude Code, the keys
# that read a pane's history are claude's own instead: prefix / is passed on
# as Ctrl-o /, and Ctrl-u and Ctrl-d as PgUp and PgDn (the @claude_pane,
# @claude_fullscreen, C-d, C-u and `bind-key /` lines of
# home/.config/tmux/tmux.conf). Anywhere else they are tmux's own. Two
# throwaway tmux servers, so no live session is touched; about 3 s.
#
#   outer server (-f /dev/null): stands in for the terminal
#     its one pane runs a client of
#   inner server (-f /dev/null + the lines under test), prefix C-b
#     one window per stand-in: a copy of bash under the name tmux is to see
#     as the pane's command, noting the code of each byte it is sent
#
#   window     named    screen     prefix /        Ctrl-u         Ctrl-d
#   full       claude   alternate  15 47           PgUp           PgDn
#                                  (Ctrl-o /)
#   versioned  2.1.330  alternate  15 47
#   classic    claude   normal     tmux's search   copy mode,     Delete
#                                                  nothing sent
#   other      vim      alternate  tmux's search   Ctrl-u         Ctrl-d
#
# A copy, not a link: on macOS tmux names a pane's command after the file
# that runs, a link's target, which is how claude comes to be `2.1.330` there.
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

command -v tmux >/dev/null || {
  echo "tmux_claude_fullscreen_test.sh: tmux not on PATH" >&2
  exit 1
}

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
CONF="$REPO/home/.config/tmux/tmux.conf"
WORK=$(mktemp -d)
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/fullscreentest.XXXXXX)
TMUX_BIN=$(command -v tmux)

# Both servers get an empty environment: no TMUX to refuse the nesting, and
# nothing of the machine's own config.
clean() { env -i HOME="$WORK" PATH=/usr/bin:/bin SHELL=/bin/sh TERM=xterm-256color "$@"; }
outer() { clean "$TMUX_BIN" -S "$SOCKDIR/outer" "$@"; }
inner() { clean "$TMUX_BIN" -S "$SOCKDIR/inner" "$@"; }

cleanup() {
  inner kill-server 2>/dev/null
  outer kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  drop_work
}
trap cleanup EXIT

# --- the lines under test -----------------------------------------------------

{
  grep -E '^set-option -g (@claude_pane|@claude_fullscreen) ' "$CONF"
  sed -n '/^bind-key -n C-d /,/^}$/p' "$CONF"
  sed -n '/^bind-key -n C-u /,/^}$/p' "$CONF"
  sed -n '/^bind-key \/ /,/^}$/p' "$CONF"
} >"$WORK/keys.conf"
if [ "$(wc -l <"$WORK/keys.conf")" -eq 13 ]; then
  pass "tmux.conf has the lines: the two rules, and C-d, C-u and prefix / with their blocks"
else
  fail "tmux.conf: expected 13 lines, got: $(cat "$WORK/keys.conf")"
fi

# --- the stand-ins ------------------------------------------------------------

# standin.sh <alternate|normal> <bytes file>: the program in a window.
# discard undef: a BSD terminal takes Ctrl-o for itself otherwise (it stops
# output), and -iexten does not last, since bash's read -n sets it again.
cat >"$WORK/standin.sh" <<'EOF'
stty -echo discard undef || exit 1
[ "$1" = alternate ] && printf '\033[?1049h'
: >"$2"
while IFS= read -r -n1 byte; do
  printf -v code '%d' "'$byte"
  printf '%s ' "$code" >>"$2"
done
EOF
mkdir "$WORK/bin"
find_copy_bash "$WORK"
for name in claude 2.1.330 vim; do cp "$COPY_BASH" "$WORK/bin/$name"; done

# --- the two servers ----------------------------------------------------------

inner -f /dev/null new-session -d -s t -n holder -x 100 -y 12
if inner source-file "$WORK/keys.conf" 2>"$WORK/out"; then
  pass "$("$TMUX_BIN" -V) takes the lines"
else
  fail "$("$TMUX_BIN" -V) refused the lines: $(cat "$WORK/out")"
fi
attach=$(printf '%q ' env -i HOME="$WORK" PATH=/usr/bin:/bin TERM=xterm-256color \
  "$TMUX_BIN" -S "$SOCKDIR/inner" attach-session -t '=t')
outer -f /dev/null new-session -d -x 100 -y 12 "$attach"

# sent <window>: the codes of the bytes the stand-in was sent, in order.
sent() { sed -E 's/ +$//' "$WORK/$1.bytes" 2>/dev/null; }
shows() { [ "$(sent "$1")" = "$2" ]; }
value() { inner display-message -p -t "t:$1" "$2"; }
is() { [ "$(value "$1" "$2")" = "$3" ]; }

# stand_in <window> <name> <alternate|normal>: the window, with tmux seeing
# the name as its pane's command and the screen it asked for. exec: tmux
# starts the command with sh -c, and dash, Ubuntu's sh, stays in front of it.
stand_in() {
  local window=$1 name=$2 screen=$3 alternate=0
  [ "$screen" = alternate ] && alternate=1
  inner new-window -d -n "$window" \
    "exec $(printf '%q ' "$WORK/bin/$name" "$WORK/standin.sh" "$screen" "$WORK/$window.bytes")"
  if until_ok 5 is "$window" '#{pane_current_command} #{alternate_on}' "$name $alternate" \
    && until_ok 5 test -e "$WORK/$window.bytes"; then
    pass "$window: tmux sees $name on the $screen screen"
  else
    fail "$window: tmux sees '$(value "$window" '#{pane_current_command} #{alternate_on}')', wanted '$name $alternate'"
  fi
}

# press <window> <key...>: the keys typed at the terminal, that window current.
press() {
  local window=$1
  shift
  inner select-window -t "t:$window"
  outer send-keys "$@"
}

# passed_on <window> <codes> <what>: the stand-in was sent those bytes, and
# tmux opened nothing of its own.
passed_on() {
  local window=$1 codes=$2 what=$3
  if until_ok 5 shows "$window" "$codes" && is "$window" '#{pane_in_mode}' 0; then
    pass "$what"
  else
    fail "$what: the pane was sent '$(sent "$window")', in copy mode: $(value "$window" '#{pane_in_mode}')"
  fi
}

# The search prompt is in the inner's bar, as the terminal shows it.
prompted() { outer capture-pane -p | grep -qF '(search up)'; }

# searched <window> <what>: tmux's own search opened, and the stand-in was
# sent nothing. Left again after: Ctrl-c ends the prompt (an Escape would
# wait escape-time and join the next key as Meta), cancel the mode.
searched() {
  local window=$1 what=$2
  if until_ok 5 is "$window" '#{pane_in_mode}' 1 && until_ok 5 prompted && shows "$window" ""; then
    pass "$what"
  else
    fail "$what: in copy mode: $(value "$window" '#{pane_in_mode}'), the pane was sent '$(sent "$window")', the terminal's last row: $(outer capture-pane -p | tail -1)"
  fi
  outer send-keys C-c
  inner send-keys -t "t:$window" -X cancel 2>/dev/null
}

stand_in full claude alternate
stand_in versioned 2.1.330 alternate
stand_in classic claude normal
stand_in other vim alternate

# --- prefix / -----------------------------------------------------------------

press full C-b /
passed_on full "15 47" "a full-screen claude: prefix / is passed on as Ctrl-o /"

press versioned C-b /
passed_on versioned "15 47" "a full-screen claude named by its version (macOS): the same"

press classic C-b /
searched classic "a claude on the normal screen: prefix / is tmux's search, its history holds the conversation"

press other C-b /
searched other "another full-screen program: prefix / is tmux's search"

# --- Ctrl-u and Ctrl-d --------------------------------------------------------

press full C-u
passed_on full "15 47 27 91 53 126" "a full-screen claude: Ctrl-u reaches it as PgUp"

press full C-d
passed_on full "15 47 27 91 53 126 27 91 54 126" "a full-screen claude: Ctrl-d reaches it as PgDn"

press classic C-d
passed_on classic "27 91 51 126" "a claude on the normal screen: Ctrl-d reaches it as Delete"

press classic C-u
if until_ok 5 is classic '#{pane_in_mode}' 1 && shows classic "27 91 51 126"; then
  pass "a claude on the normal screen: Ctrl-u is copy mode, and it is sent nothing"
else
  fail "a claude on the normal screen: Ctrl-u: in copy mode: $(value classic '#{pane_in_mode}'), the pane was sent '$(sent classic)'"
fi

press other C-u
passed_on other "21" "another full-screen program: Ctrl-u reaches it as Ctrl-u"

press other C-d
passed_on other "21 4" "another full-screen program: Ctrl-d reaches it as Ctrl-d"

finish
