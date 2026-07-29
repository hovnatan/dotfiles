#!/bin/bash
# PreToolUse hook (Bash matcher): deterministic enforcement of the CLAUDE.md
# git rules. git commit / git push (force pushes included) always get a
# permission prompt so the user approves each one explicitly.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

case "$cmd" in
  *git*) ;;
  *) exit 0 ;;
esac

emit() {
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

force_re='(^|[[:space:]])(--force-with-lease(=[^[:space:]]*)?|--force|-f)([[:space:]]|$)'
ask_reason=''

# Split compound commands on ; & | and inspect each simple command.
while IFS= read -r seg; do
  [[ $seg =~ (^|[[:space:]])git[[:space:]] ]] || continue
  if [[ $seg =~ (^|[[:space:]])push([[:space:]]|$) ]]; then
    if [[ $seg =~ $force_re ]]; then
      emit ask "FORCE PUSH - requires explicit user approval (git-guard hook, per CLAUDE.md: never force push unless explicitly requested)."
    fi
    ask_reason='git push requires explicit user approval (git-guard hook, per CLAUDE.md).'
  elif [[ $seg =~ (^|[[:space:]])commit([[:space:]]|$) ]]; then
    : "${ask_reason:=git commit requires explicit user approval (git-guard hook, per CLAUDE.md).}"
  fi
done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n')"

if [[ -n $ask_reason ]]; then
  emit ask "$ask_reason"
fi
exit 0
