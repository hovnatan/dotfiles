#!/usr/bin/env bash
#
# claude_transcript_test.sh -- home/.config/tmux/claude-transcript.sh: the
# SessionStart hook that notes a conversation's transcript on its tmux pane,
# and the text of that transcript, which extrakto offers. A throwaway tmux
# server and HOME, so no live session and no real transcript is touched;
# about 3 s. Needs tmux, jq, perl and python3.
#
#   window  runs                     the hook, run under it       text <pane> <lines>
#   chat    claude (a copy of bash)  @claude_transcript is the    the conversation
#           and under it, cut off    input's path
#           from the terminal, a     passed over: the option
#           second claude            stays the first one's
#   shell   sh                                                    nothing, though
#                                                                 the option is set
#
# The second claude is what `claude -p` run by a tool call is: it inherits
# TMUX_PANE and has no terminal.
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux jq perl python3; do
  command -v "$cmd" >/dev/null || {
    echo "claude_transcript_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
WORK=$(mktemp -d)
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/transcripttest.XXXXXX)
SOCK="$SOCKDIR/default"
TMUX_BIN=$(command -v tmux)
SERVER_PATH="$(dirname "$TMUX_BIN"):$(dirname "$(command -v jq)"):/usr/bin:/bin"

# Its event log is under HOME, the throwaway one here.
SCRIPT="$REPO/home/.config/tmux/claude-transcript.sh"
mkdir "$WORK/bin"

t() { env -i HOME="$WORK" PATH="$SERVER_PATH" TERM=xterm-256color "$TMUX_BIN" -S "$SOCK" "$@"; }
# script <arguments...>: the script as a process of the server's runs it.
script() { env -i HOME="$WORK" PATH="$SERVER_PATH" TMUX="$SOCK,0,0" "$SCRIPT" "$@"; }
noted() { t display-message -p -t "$1" '#{@claude_transcript}'; }
logged() { grep -h "$1" "$WORK"/.dotfiles/.logs/*_tmux_hooks/events.log 2>/dev/null; }
# fails_with <pattern> <what> <command...>: the command fails, saying the pattern
fails_with() {
  local pattern=$1 what=$2 out
  shift 2
  if out=$("$@" 2>&1); then
    fail "$what did not fail: $out"
    return
  fi
  # shellcheck disable=SC2254 # a pattern
  case "$out" in
    $pattern) pass "$what fails and says so" ;;
    *) fail "$what failed with: $out" ;;
  esac
}

cleanup() {
  t kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  drop_work
}
trap cleanup EXIT

# --- a transcript -------------------------------------------------------------

long=$(printf 'x%.0s' $(seq 2100))
cat >"$WORK/first.jsonl" <<EOF
{"type":"user","message":{"role":"user","content":"where is ledger_reconcile.py?"}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"meta_only_word"}}
{"type":"ai-title","title":"title_only_word"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"thinking_only_word"},{"type":"text","text":"It is under src/billing."},{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/repo/src/billing/ledger_reconcile.py","limit":5}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"result_start $long result_end"}]}]}}
{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"sidechain_only_word"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"git log --oneline","description":"Show the log"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"b2df4e75 a commit"}]}}
EOF

# --- the server ---------------------------------------------------------------

grep -E '^set-option -g @claude_pane ' "$REPO/home/.config/tmux/tmux.conf" >"$WORK/rule.conf"
t -f /dev/null new-session -d -s t -n shell -x 100 -y 12 "exec sh"
t source-file "$WORK/rule.conf" || fail "tmux refused the @claude_pane line: $(cat "$WORK/rule.conf")"

# The claude of the chat window: the hook under it, then the hook under a
# second claude with no terminal (perl, since macOS has no setsid command),
# then a wait on the terminal, with no other program in front of it. Each
# claude names itself to its hook, as a real one does.
cat >"$WORK/chat.sh" <<EOF
export CLAUDE_PID=\$\$
printf '{"transcript_path":"%s"}' "$WORK/first.jsonl" | "$SCRIPT" note
echo "\$?" >"$WORK/first.status"
perl -MPOSIX -e 'setsid(); exec @ARGV' "$WORK/bin/claude" "$WORK/tool.sh"
echo done >"$WORK/chat.done"
read -r _
EOF
cat >"$WORK/tool.sh" <<EOF
export CLAUDE_PID=\$\$
printf '{"transcript_path":"%s"}' "$WORK/second.jsonl" | "$SCRIPT" note
echo "\$?" >"$WORK/second.status"
EOF
find_copy_bash "$WORK"
cp "$COPY_BASH" "$WORK/bin/claude"
t new-window -d -n chat "$(printf '%q ' "$WORK/bin/claude" "$WORK/chat.sh")"
chat=$(t display-message -p -t t:chat '#{pane_id}')
shell=$(t display-message -p -t t:shell '#{pane_id}')
until_ok 10 test -e "$WORK/chat.done" || fail "the chat window's claude never ran both hooks"

# --- note ---------------------------------------------------------------------

if [ "$(cat "$WORK/first.status")" = 0 ] && [ "$(noted "$chat")" = "$WORK/first.jsonl" ] \
  && logged "claude-transcript note $chat: $WORK/first.jsonl" >/dev/null; then
  pass "the hook under the pane's claude: the pane's @claude_transcript is the input's path, and the log says so"
else
  fail "the hook under the pane's claude: status $(cat "$WORK/first.status" 2>&1), the pane holds '$(noted "$chat")', log: $(logged claude-transcript)"
fi

if [ "$(cat "$WORK/second.status")" = 0 ] && [ "$(noted "$chat")" = "$WORK/first.jsonl" ] \
  && logged "claude-transcript note $chat: passed over, .*$WORK/second.jsonl" >/dev/null; then
  pass "the hook under a claude with no terminal (claude -p from a tool call): passed over, said in the log"
else
  fail "the hook under a claude with no terminal: status $(cat "$WORK/second.status" 2>&1), the pane holds '$(noted "$chat")', log: $(logged claude-transcript)"
fi

if out=$(echo '{"transcript_path":"/nowhere"}' | env -i HOME="$WORK" PATH="$SERVER_PATH" "$SCRIPT" note 2>&1) && [ -z "$out" ]; then
  pass "the hook outside tmux: nothing to note, and no failure"
else
  fail "the hook outside tmux: $out"
fi

# hook <input>: the hook in the chat pane, with no claude named to it
hook() { echo "$1" | env -i HOME="$WORK" PATH="$SERVER_PATH" TMUX="$SOCK,0,0" TMUX_PANE="$chat" "$SCRIPT" note; }
fails_with '*names no transcript_path*' "the hook with no transcript_path in its input" hook '{"source":"startup"}'
fails_with '*CLAUDE_PID is not set*' "the hook with no CLAUDE_PID" hook '{"transcript_path":"/nowhere"}'

# --- text ---------------------------------------------------------------------

script text "$chat" 2000 >"$WORK/text" 2>"$WORK/text.err" || fail "text $chat 2000 failed: $(cat "$WORK/text.err")"
want="where is ledger_reconcile.py?
It is under src/billing.
/repo/src/billing/ledger_reconcile.py
result_start $(printf 'x%.0s' $(seq 1987))
git log --oneline
Show the log
b2df4e75 a commit"
if [ "$(cat "$WORK/text")" = "$want" ]; then
  pass "text: what was typed and said, each tool call's input, 2000 characters of each result; no thinking, meta, subagent or other record"
else
  fail "text: got $(cut -c1-120 "$WORK/text")"
fi
logged "claude-transcript text $chat: the last 2000 of 7 lines of $WORK/first.jsonl" >/dev/null \
  || fail "no line for the use in the log: $(logged 'claude-transcript text')"

if [ "$(script text "$chat" 3 2>&1)" = "$(printf '%s\n' "$want" | tail -n 3)" ]; then
  pass "text of 3 lines: the conversation's last 3"
else
  fail "text of 3 lines: got $(script text "$chat" 3 2>&1 | cut -c1-120)"
fi

fails_with 'usage:*' "text with no number of lines" script text "$chat"

t set-option -p -t "$shell" @claude_transcript "$WORK/first.jsonl"
if out=$(script text "$shell" 2000 2>&1) && [ -z "$out" ]; then
  pass "text for a pane no claude runs in: nothing, though a transcript was noted there"
else
  fail "text for a pane no claude runs in: $out"
fi

chmod 000 "$WORK/first.jsonl"
fails_with '*cannot be read*' "text of a transcript that cannot be read" script text "$chat" 2000

# A conversation's file is written at its first prompt, after the hook.
rm -f "$WORK/first.jsonl"
if out=$(script text "$chat" 2000 2>&1) && [ -z "$out" ] \
  && logged "claude-transcript text $chat: no transcript file yet: $WORK/first.jsonl" >/dev/null; then
  pass "text before the transcript file exists: nothing, no failure, said in the log"
else
  fail "text before the transcript file exists: $out, log: $(logged 'claude-transcript text')"
fi

finish
