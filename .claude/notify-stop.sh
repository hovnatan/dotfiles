#!/bin/sh
# Claude Code Stop hook: ring the bell and post a Ghostty desktop
# notification (OSC 777) when Claude finishes responding. Hook processes
# may lack a controlling tty (/dev/tty fails), so walk up the process tree
# to the claude process and write to its terminal device directly. Inside
# tmux the OSC needs the passthrough envelope (allow-passthrough in
# .tmux.conf), while the bell is forwarded natively.

# Inside tmux, skip entirely while a client of this session is focused:
# the user is already looking at the pane, so a bell would only annoy.
# The session id rides in $TMUX (socket-path,server-pid,session-id), so
# no name lookup is needed. Detached or attached-but-blurred sessions
# fall through to the bell as before. Same predicate as ntfy-stop.sh's
# client_flags -- keep the two in sync.
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
{
  printf '\a' > "$T"
  if [ -n "$TMUX" ]; then
    printf '\033Ptmux;\033\033]777;notify;Claude Code;Finished responding\007\033\\' > "$T"
  else
    printf '\033]777;notify;Claude Code;Finished responding\007' > "$T"
  fi
} 2>/dev/null
exit 0
