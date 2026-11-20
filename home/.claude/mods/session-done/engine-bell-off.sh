#!/usr/bin/env bash
# engine-bell-off.sh -- turn Claude Code's own idle bell off, so that the
# bell of the session-done mod it belongs to is the only one
# (hooks/register.ts has why). The mod runs this at each session's start.
#
#   engine-bell-off.sh  -> exit 0, printing "was 60000" (the value it
#                          replaced; "was unset" for none) when it changed
#                          the file, and nothing when the bell was off already
#                          exit 1 and the reason on stderr when it cannot
#
# The bell is the `idle_prompt` notification, raised
# messageIdleNotifThresholdMs after a turn's end (60000 when unset). The key
# is read from claude's state file alone, ~/.claude.json: it has no
# settings.json key, no /config row and no environment variable (Claude Code
# 2.1.329), and no "never" either, so it is set to the longest wait a timer
# takes, 2^31-1 ms (24.8 days). A running claude reads the file afresh, so
# the change holds from its next turn end (seen live, 2026-11-19).
#
# Every running claude rewrites that file. The new copy is renamed into
# place, so no reader sees half a file, but an update a claude writes
# between this script's read and its rename is lost (a counter, a tip's
# history). That is why it writes only when the value differs: once a
# machine, not once a session.
#
# The setting outlives the mod. With the mod gone, or no longer loading (a
# claude started with hooks off, a Claude Code whose mod API moved on),
# nothing rings after a turn at all, and nothing says so: the mod's "session:
# started" line, one at each claude start, stops coming to its log
# (~/.dotfiles/.logs/*_claude_session_done/events.log). To undo:
#   jq 'del(.messageIdleNotifThresholdMs)' ~/.claude.json, written back the same way

set -euo pipefail

OFF=2147483647
# Where claude keeps the file: its config directory when one is named.
file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"

[ -f "$file" ] || {
  echo "engine-bell-off.sh: no $file, where Claude Code keeps messageIdleNotifThresholdMs" >&2
  exit 1
}

was=$(jq -r '.messageIdleNotifThresholdMs // "unset"' "$file")
[ "$was" = "$OFF" ] && exit 0

# Beside the file, so the rename stays on one filesystem; mktemp makes it
# readable by its owner alone, as the file is (it holds the account).
tmp=$(mktemp "$file.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --argjson off "$OFF" '.messageIdleNotifThresholdMs = $off' "$file" >"$tmp"
mv "$tmp" "$file"

echo "was $was"
