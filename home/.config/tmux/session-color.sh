#!/usr/bin/env bash
# Claude Code SessionStart hook (matcher "clear"): carry a session's
# prompt-bar color -- what /color set -- across /clear, by typing /color
# into the session's own pane.
#
# Why. /clear starts a fresh conversation and carries the title and agent
# name over to it, but not the color: of the three sibling records it
# saves, agent-color is the one it never writes (2.1.260). Nothing sets the
# color from outside a live session -- --agent-color is a teammate knob
# that paints nothing on a plain session, a record appended to the
# transcript is read only by the next resume, and the hook's own
# initialUserMessage output is consumed at startup, not after a clear --
# so the one live path is the command itself. This script retires the day
# /clear carries agent-color, or consumes initialUserMessage on clear.
# Only clear: a resume restores the color itself, and a fresh start under
# a name that has older conversations is a choice not to continue them.
#
#   /clear --> SessionStart --> title + transcript path from the hook JSON
#                               previous conversation under that title
#                               --> its last color --> send-keys "/color <c>"
#
# The keys go straight in: after a /clear the process and its input box
# are the ones already on screen, and Claude Code reads the tty while the
# hook runs (checked: the command lands and runs before the hook returns).
# On startup that would be unsafe -- the trust dialog of an unseen
# directory takes Enter as "No, exit" -- hence the source check below as
# well as the matcher.
#
# Portability as ntfy-stop.sh: sed for the hook JSON, no tac, no xargs -r.
set -u

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0   # not a tmux-hosted session
socket=${TMUX%%,*}
input=$(cat)
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" <<<"$input"; }
source=$(field source) transcript=$(field transcript_path) title=$(field session_title)
[ "$source" = clear ] && [ -n "$transcript" ] && [ -n "$title" ] || exit 0

# Type only into a claude that holds its terminal's foreground group. That
# is the session the user sees; a nested claude -- a `claude -p` run from
# a session's Bash tool inherits $TMUX_PANE -- has no controlling tty at
# all, so typing on its behalf would land in the PARENT's pane. CLAUDE_PID
# is the claude running this hook.
if [ -z "${CLAUDE_PID:-}" ]; then
  echo "session-color.sh: CLAUDE_PID missing from the hook environment" >&2
  exit 1
fi
read -r pgid tpgid < <(ps -o pgid=,tpgid= -p "$CLAUDE_PID" 2>/dev/null)
[ -n "${pgid:-}" ] && [ "$pgid" = "${tpgid:-}" ] || exit 0

# The conversation just cleared: the newest transcript in the same project
# directory, other than the one being started, whose LAST custom-title
# record carries this title (renames append; the ^ anchor keeps lines that
# merely quote such a record from matching). Its last agent-color record is
# the color. Only each file's tail is read: Claude Code rewrites the title,
# name and color records every turn, so the last of each sits within
# kilobytes of the end, while whole files reach 40 MB and reading them
# cold blew the hook's 5s budget. Same reading as resolve_conversation in
# claude_tmux_run.sh -- change both together.
color=""
for f in $(ls -t "$(dirname "$transcript")"/*.jsonl 2>/dev/null); do
  [ "$f" != "$transcript" ] || continue
  IFS=$'\t' read -r ok c < <(tail -c 1048576 "$f" |
    awk -v want="\"customTitle\":\"$title\"" '
      /^\{"type":"custom-title"/ { ok = index($0, want) > 0 }
      /^\{"type":"agent-color"/  { c = $0; sub(/.*"agentColor":"/, "", c); sub(/".*/, "", c) }
      END { print ok "\t" c }')
  [ "${ok:-}" = 1 ] || continue
  color=$c
  break
done
case "$color" in ''|default) exit 0 ;; esac

tmux -S "$socket" send-keys -t "$TMUX_PANE" -l "/color $color" \; send-keys -t "$TMUX_PANE" Enter
exit 0
