#!/usr/bin/env bash
#
# claude-transcript.sh -- a tmux pane knows the transcript file of the Claude
# Code conversation in it, and extrakto (prefix Tab) offers that
# conversation's words with the pane's own. The pane shows a part of the
# conversation at most: its history is cut at history-limit and wraps a long
# path, and for a full-screen claude (/tui fullscreen) it holds one screen.
#
#   claude-transcript.sh note         a SessionStart hook (settings.json), its
#                                     JSON on stdin: the pane's
#                                     @claude_transcript is the transcript's path
#   claude-transcript.sh text <pane> <lines>
#                                     the last lines of the conversation as
#                                     plain text, oldest first; nothing for a
#                                     pane no claude runs in. Run by extrakto,
#                                     as its @extrakto_extra_command
#                                     (tmux.conf), with as many lines as it
#                                     takes of a pane's history.
#
# The hook runs at every start of a conversation in a claude: its own start,
# /clear, /resume, a compaction. A claude (CLAUDE_PID, which it gives its
# hooks) whose terminal is not the pane's is passed over: `claude -p` run by
# a tool call inherits TMUX_PANE from the pane's claude, and its conversation
# is not the pane's.
#
# text holds what was typed and said, each tool call's input and the start
# of each result. A transcript keeps what a compaction dropped, so the lines
# reach back past one.
#
# A line a use in ~/.dotfiles/.logs/<day>_tmux_hooks/events.log.
#
# Runs under bash 3.2 too: extrakto finds bash on the tmux server's PATH.
set -euo pipefail

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"

OPTION=@claude_transcript
# Of a tool call's input and result, each string's first characters: a file
# read whole is not the conversation.
TOOL_CHARS=2000

failed() {
  event_log_note tmux_hooks "claude-transcript $1: FAILED, $2"
  echo "claude-transcript.sh $1: $2" >&2
  exit 1
}

note() {
  [ -n "${TMUX_PANE:-}" ] || exit 0
  local path tty pane_tty
  path=$(jq -er '.transcript_path') || failed note "the hook's input names no transcript_path"
  [ -n "${CLAUDE_PID:-}" ] || failed note "CLAUDE_PID is not set: claude gives its hooks its own process id from 2.1.214 on"
  tty=$(ps -o tty= -p "$CLAUDE_PID") || failed note "no process $CLAUDE_PID, the hook's CLAUDE_PID"
  tty=${tty// /}
  pane_tty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}')
  if [ "/dev/$tty" != "$pane_tty" ]; then
    event_log_note tmux_hooks "claude-transcript note $TMUX_PANE: passed over, its claude has no terminal of the pane's ($tty): $path"
    exit 0
  fi
  tmux set-option -p -t "$TMUX_PANE" "$OPTION" "$path"
  event_log_note tmux_hooks "claude-transcript note $TMUX_PANE: $path"
}

text() {
  local pane=$1 count=$2 path lines
  path=$(tmux display-message -p -t "$pane" "#{?#{E:@claude_pane},#{$OPTION},}")
  [ -n "$path" ] || exit 0
  # claude writes the file at the conversation's first prompt, after the hook.
  if [ ! -e "$path" ]; then
    event_log_note tmux_hooks "claude-transcript text $pane: no transcript file yet: $path"
    exit 0
  fi
  [ -r "$path" ] || failed text "pane $pane names a transcript that cannot be read: $path"
  # shellcheck disable=SC2016  # a jq program: $n is jq's variable, not the shell's
  lines=$(jq -r --argjson n "$TOOL_CHARS" '
    select(.type == "user" or .type == "assistant")
    | select(.isMeta != true and .isSidechain != true)
    | .message.content
    | if type == "string" then .
      else .[]
        | if .type == "text" then .text
          elif .type == "tool_use" then .input | [.. | strings | .[0:$n]] | join("\n")
          elif .type == "tool_result" then
            .content
            | if type == "string" then .[0:$n]
              else [.[] | select(.type == "text") | .text] | join("\n") | .[0:$n]
              end
          else empty
          end
      end' "$path") || failed text "jq could not read $path"
  printf '%s\n' "$lines" | tail -n "$count"
  event_log_note tmux_hooks "claude-transcript text $pane: the last $count of $(printf '%s\n' "$lines" | wc -l | tr -d ' ') lines of $path"
}

usage() {
  echo "usage: claude-transcript.sh note | text <pane id> <lines>" >&2
  exit 2
}

case "${1:-}" in
  note) note ;;
  text)
    { [ $# -eq 3 ] && [[ $3 =~ ^[0-9]+$ ]]; } || usage
    text "$2" "$3"
    ;;
  *) usage ;;
esac
