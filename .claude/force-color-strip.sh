#!/bin/bash
# PreToolUse hook (Bash matcher): the claude-tmux launcher starts claude
# with FORCE_COLOR=3 (truecolor for detached spawns, see
# scripts/claude_tmux_run.sh), and tool subshells inherit it, making node
# CLIs write ANSI into pipes. Strip it by prefixing the command. No-op
# when FORCE_COLOR is not in claude's environment.
set -euo pipefail

[ -n "${FORCE_COLOR:-}" ] || exit 0

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

jq -cn --arg c "unset FORCE_COLOR; $cmd" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: {command: $c}}}'
