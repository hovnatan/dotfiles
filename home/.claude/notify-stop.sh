#!/bin/sh
# Claude Code Stop hook: ring the bell and post a desktop notification
# (Ghostty and iTerm2) when Claude finishes responding. Hook processes
# may lack a controlling tty (/dev/tty fails), so walk up the process tree
# to the claude process and write to its terminal device directly. Inside
# tmux the OSC needs the passthrough envelope (allow-passthrough in
# .tmux.conf), while the bell is forwarded natively.

# Inside tmux, skip entirely while a client of this session is focused:
# the user is already looking at the pane, so a bell would only annoy.
# The session id rides in $TMUX (socket-path,server-pid,session-id), so
# no name lookup is needed. Detached or attached-but-blurred sessions
# fall through to the bell as before. ntfy-stop.sh's watched() derives
# the target the same way but adds a freshness bound on purpose -- a bell
# into a locked screen is harmless, a suppressed push is not.
if [ -n "${TMUX:-}" ]; then
  case $(tmux -S "${TMUX%%,*}" list-clients -t "\$${TMUX##*,}" \
      -F '#{client_flags}' 2>/dev/null) in
  *focused*) exit 0 ;;
  esac
fi

# Inside tmux the pane's tty is one ~2ms query away; the ps walk below
# costs ~8x per iteration, so keep it only as the non-tmux fallback.
T=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
  T=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
fi
if [ -z "$T" ]; then
  p=$PPID
  t=""
  i=0
  while [ "$i" -lt 5 ] && [ -n "$p" ] && [ "$p" != "1" ]; do
    t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
    # "??" (macOS) and "?" (Linux) mean no controlling tty; keep walking up
    case "$t" in
      ""|"?"|"??") ;;
      *) break ;;
    esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  case "$t" in
    ""|"?"|"??") exit 0 ;;
  esac
  T="/dev/$t"
fi

# The notification goes out in two dialects and each terminal ignores the
# other's: OSC 777 for Ghostty, OSC 1337 Notification (base64 fields) for
# iTerm2, which does not parse 777. Inside tmux every ESC is doubled and the
# lot wrapped in the passthrough envelope.
title="Claude Code"
body="Finished responding"
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
if [ -n "${TMUX:-}" ]; then
  e='\033\033' pre='\033Ptmux;' post='\033\\'
else
  e='\033' pre='' post=''
fi
{
  printf '\a' > "$T"
  printf "$pre$e]777;notify;%s;%s\007$e]1337;Notification=title=%s;message=%s\007$post" \
    "$title" "$body" "$(b64 "$title")" "$(b64 "$body")" > "$T"
} 2>/dev/null
exit 0
