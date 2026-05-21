#!/usr/bin/env bash
# PreToolUse hook (matcher: "Skill") — records every Claude Code skill invocation.
#
# Claude Code runs a skill by calling the "Skill" tool, so a PreToolUse hook on
# that tool fires once per skill use. The hook payload arrives as JSON on stdin.
# This script appends a tab-separated line (timestamp, skill, session id) to the
# log, and emits a {"systemMessage": ...} so the invocation is also visible live
# in the session.
#
# Wired up in ~/.dotfiles/.claude/settings.json under hooks.PreToolUse.
# Override the log path with CLAUDE_SKILL_LOG.

set -uo pipefail

LOG="${CLAUDE_SKILL_LOG:-$HOME/.claude/skill-usage.log}"
payload=$(cat)

if command -v jq >/dev/null 2>&1; then
  skill=$(printf '%s' "$payload" | jq -r '.tool_input.skill // "?"')
  session=$(printf '%s' "$payload" | jq -r '.session_id // "?"')
else
  skill=$(printf '%s' "$payload" \
    | grep -oE '"skill"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
    | sed -E 's/.*"([^"]*)"$/\1/')
  session="?"
fi
[ -n "$skill" ] || skill="?"

mkdir -p "$(dirname "$LOG")"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$skill" "$session" >> "$LOG"

# Live, in-session signal (skill names are [a-z0-9:-], so JSON-safe verbatim).
printf '{"systemMessage": "skill invoked: %s"}\n' "$skill"
exit 0
